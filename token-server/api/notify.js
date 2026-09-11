// ConnectCall push endpoint (bonus features 1 and 2).
//
// Wakes the callee's phone so a call rings even when their app is closed.
//
//   POST /api/notify
//   Authorization: Bearer <Firebase ID token>
//   { "callId": "...", "event": "ring" | "cancel" }
//
//   200 { delivered: true }
//   200 { delivered: false, reason }   callee has no push-capable device
//
// Only the call's *caller* may notify, and only about their own call: the
// requester is verified exactly as in /api/token (ID token, then a read of the
// call with their own token), and must additionally be its callerId. So nobody
// can make someone's phone ring for a call that does not exist, or ring
// themselves back as the callee.
//
// Device tokens live at fcm_tokens/{uid}, readable only by their owner under
// the database rules. This server reads the callee's token with the Firebase
// Admin SDK, which is why it needs a service account (unlike /api/token).

import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getDatabase } from 'firebase-admin/database';
import { getMessaging } from 'firebase-admin/messaging';

import {
  HttpError,
  bearerToken,
  parseBody,
  parseCallId,
  readCallAsUser,
  readFirebaseConfig,
  sendError,
  verifyFirebaseUser,
} from '../lib/shared.js';

const EVENTS = new Set(['ring', 'cancel']);
const RINGABLE = new Set(['calling', 'ringing']);

/// Matches the app's ring timeout: a ring that arrives later than this is
/// stale, so FCM may drop it rather than wake the phone for a dead call.
const RING_TTL_MS = 45_000;
const CANCEL_TTL_MS = 60_000;

export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');

  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const { projectId, databaseUrl } = readFirebaseConfig();
    const serviceAccount = readServiceAccount();
    const idToken = bearerToken(req);
    const uid = await verifyFirebaseUser(idToken, projectId);

    const body = parseBody(req.body);
    const callId = parseCallId(body);
    const event = body?.event;
    if (!EVENTS.has(event)) {
      throw new HttpError(400, 'event must be "ring" or "cancel".');
    }

    const call = await readCallAsUser(databaseUrl, callId, idToken);
    if (call.callerId !== uid) {
      throw new HttpError(403, 'Only the caller can notify about this call.');
    }
    if (event === 'ring' && !RINGABLE.has(call.status)) {
      throw new HttpError(409, 'This call is no longer ringing.');
    }

    const app = adminApp(serviceAccount, databaseUrl);
    const tokenRef = getDatabase(app).ref(`fcm_tokens/${call.receiverId}`);
    const deviceToken = (await tokenRef.get()).val();
    if (typeof deviceToken !== 'string' || deviceToken.length === 0) {
      // Not an error: the callee may never have opened the app on a device
      // that supports push. The in-app listener still rings them if it is open.
      return res.status(200).json({ delivered: false, reason: 'no-device-token' });
    }

    try {
      await getMessaging(app).send({
        token: deviceToken,
        // Data-only (no "notification" block), so the app's background handler
        // decides how to present it: a full-screen incoming-call UI for a
        // ring, dismissing that UI for a cancel.
        data: {
          type: event === 'ring' ? 'incoming_call' : 'call_cancelled',
          callId,
          callerId: String(call.callerId ?? ''),
          callerName: String(call.callerName ?? 'Someone'),
          callType: call.type === 'video' ? 'video' : 'audio',
        },
        android: {
          priority: 'high',
          ttl: event === 'ring' ? RING_TTL_MS : CANCEL_TTL_MS,
        },
      });
    } catch (error) {
      if (error?.code === 'messaging/registration-token-not-registered') {
        // The app was uninstalled or the token rotated: drop the stale token.
        await tokenRef.remove().catch(() => {});
        return res.status(200).json({ delivered: false, reason: 'stale-token' });
      }
      throw error;
    }

    return res.status(200).json({ delivered: true });
  } catch (error) {
    return sendError(res, error, 'Could not notify the other person.');
  }
}

function readServiceAccount() {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!raw) {
    console.error('notify: missing FIREBASE_SERVICE_ACCOUNT');
    throw new HttpError(500, 'Push notifications are not configured.');
  }
  try {
    return JSON.parse(raw);
  } catch {
    console.error('notify: FIREBASE_SERVICE_ACCOUNT is not valid JSON');
    throw new HttpError(500, 'Push notifications are not configured.');
  }
}

/// One Admin SDK app per warm function instance.
function adminApp(serviceAccount, databaseUrl) {
  const existing = getApps();
  if (existing.length > 0) return existing[0];
  return initializeApp({ credential: cert(serviceAccount), databaseURL: databaseUrl });
}
