// ConnectCall token server.
//
// Mints an Agora RTC token for one call, and only for someone who is really
// one of its two participants.
//
//   POST /api/token
//   Authorization: Bearer <Firebase ID token>
//   { "callId": "<calls/{callId} key>" }
//
//   200 { token, rtcUid, channelName, expiresIn }
//
// How participation is proven, without a Firebase service account:
//
//   1. The Firebase ID token is verified against Google's public signing keys.
//      That proves who is asking.
//   2. calls/{callId} is read over the Realtime Database REST API *using the
//      caller's own ID token*. The deployed database rules only let the call's
//      caller and receiver read it, so a successful read proves the requester
//      is a participant. The uid comparison afterwards is a second check, not
//      the only one.
//
// The channel name and Agora uid are taken from the database and derived from
// the verified Firebase uid respectively. Neither is accepted from the client,
// so a participant cannot mint a token for some other channel or impersonate
// the other party's uid.
//
// The App Certificate lives only in this server's environment. It is never
// sent to the app, which is the whole point: a certificate shipped in an APK
// can be extracted and used to mint tokens for any channel.

import agoraToken from 'agora-token';
import { createRemoteJWKSet, jwtVerify } from 'jose';

const { RtcTokenBuilder, RtcRole } = agoraToken;

/// Tokens outlive any realistic call setup; the app renews before expiry
/// for long calls via Agora's onTokenPrivilegeWillExpire callback.
const TOKEN_TTL_SECONDS = 3600;

/// Realtime Database push keys are 20 characters of [A-Za-z0-9_-]. Anything
/// else is rejected before it can reach a database path, so input like
/// "../users" cannot walk the tree.
const CALL_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

/// Characters Agora accepts in a channel name, per its token builder docs.
const CHANNEL_PATTERN = /^[A-Za-z0-9 !#$%&()+\-:;<=.>?@[\]^_{|}~,]{1,64}$/;

/// A call in any of these states is over. Issuing a token for it would let a
/// former participant reopen the channel.
const TERMINAL_STATUSES = new Set([
  'ended',
  'rejected',
  'missed',
  'busy',
  'failed',
  'disconnected',
]);

const GOOGLE_SECURETOKEN_JWKS = createRemoteJWKSet(
  new URL(
    'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com',
  ),
);

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');

  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const config = readConfig();
    const idToken = bearerToken(req);
    const uid = await verifyFirebaseUser(idToken, config.projectId);
    const callId = parseCallId(req.body);
    const call = await readCallAsUser(config.databaseUrl, callId, idToken);

    if (call.callerId !== uid && call.receiverId !== uid) {
      throw new HttpError(403, 'You are not a participant in this call.');
    }
    if (TERMINAL_STATUSES.has(call.status)) {
      throw new HttpError(409, 'This call has already ended.');
    }
    if (typeof call.channelName !== 'string' || !CHANNEL_PATTERN.test(call.channelName)) {
      throw new HttpError(422, 'This call has an invalid channel.');
    }

    const rtcUid = rtcUidFor(uid);
    const token = RtcTokenBuilder.buildTokenWithUid(
      config.appId,
      config.appCertificate,
      call.channelName,
      rtcUid,
      RtcRole.PUBLISHER,
      TOKEN_TTL_SECONDS,
      TOKEN_TTL_SECONDS,
    );

    return res.status(200).json({
      token,
      rtcUid,
      channelName: call.channelName,
      expiresIn: TOKEN_TTL_SECONDS,
    });
  } catch (error) {
    if (error instanceof HttpError) {
      return res.status(error.status).json({ error: error.message });
    }
    // Unexpected failures are logged server-side only. The client gets a
    // generic message, never a stack trace or configuration detail.
    console.error('token-server: unexpected error', error);
    return res.status(500).json({ error: 'Could not issue a call token.' });
  }
}

function readConfig() {
  const appId = process.env.AGORA_APP_ID;
  const appCertificate = process.env.AGORA_APP_CERTIFICATE;
  const projectId = process.env.FIREBASE_PROJECT_ID;
  const databaseUrl = process.env.FIREBASE_DATABASE_URL?.replace(/\/+$/, '');

  if (!appId || !appCertificate || !projectId || !databaseUrl) {
    // Logged with names only, never values.
    console.error('token-server: missing one of AGORA_APP_ID, AGORA_APP_CERTIFICATE, FIREBASE_PROJECT_ID, FIREBASE_DATABASE_URL');
    throw new HttpError(500, 'The call service is not configured.');
  }
  return { appId, appCertificate, projectId, databaseUrl };
}

function bearerToken(req) {
  const header = req.headers.authorization ?? '';
  const match = /^Bearer\s+(.+)$/i.exec(header);
  if (!match) throw new HttpError(401, 'Missing sign-in credentials.');
  return match[1].trim();
}

async function verifyFirebaseUser(idToken, projectId) {
  try {
    const { payload } = await jwtVerify(idToken, GOOGLE_SECURETOKEN_JWKS, {
      issuer: `https://securetoken.google.com/${projectId}`,
      audience: projectId,
      algorithms: ['RS256'],
    });
    if (typeof payload.sub !== 'string' || payload.sub.length === 0) {
      throw new Error('token has no subject');
    }
    return payload.sub;
  } catch {
    // Expired, malformed, wrong project, or bad signature all look the same to
    // the client: sign in again. The app retries once with a refreshed token.
    throw new HttpError(401, 'Your session has expired. Please sign in again.');
  }
}

function parseCallId(body) {
  let parsed = body;
  if (typeof parsed === 'string') {
    try {
      parsed = JSON.parse(parsed);
    } catch {
      throw new HttpError(400, 'Request body must be JSON.');
    }
  }
  const callId = parsed?.callId;
  if (typeof callId !== 'string' || !CALL_ID_PATTERN.test(callId)) {
    throw new HttpError(400, 'A valid callId is required.');
  }
  return callId;
}

async function readCallAsUser(databaseUrl, callId, idToken) {
  const url = `${databaseUrl}/calls/${callId}.json?auth=${encodeURIComponent(idToken)}`;

  let response;
  try {
    response = await fetch(url);
  } catch {
    throw new HttpError(502, 'Could not reach the call database.');
  }

  // The rules deny reads to non-participants, and also to calls that do not
  // exist (the rule compares against callerId, which is null for a missing
  // node). Both cases are reported the same way, so this endpoint cannot be
  // used to probe which call ids exist.
  if (response.status === 401 || response.status === 403) {
    throw new HttpError(403, 'You are not a participant in this call.');
  }
  if (!response.ok) {
    throw new HttpError(502, 'Could not reach the call database.');
  }

  const call = await response.json();
  if (!call || typeof call !== 'object') {
    throw new HttpError(403, 'You are not a participant in this call.');
  }
  return call;
}

/// Maps a Firebase uid to a stable Agora uid with 32-bit FNV-1a.
///
/// The result is kept in 1..2^31-1: Agora forbids 0 for authenticated joins,
/// and staying below 2^31 means it is a positive signed 32-bit int, so the
/// Dart and Java layers never see it wrap negative. Only the two participants
/// of one call ever share a channel, so a hash collision between them is
/// vanishingly unlikely.
function rtcUidFor(firebaseUid) {
  let hash = 0x811c9dc5;
  for (let i = 0; i < firebaseUid.length; i++) {
    hash ^= firebaseUid.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return (hash % 0x7ffffffe) + 1;
}
