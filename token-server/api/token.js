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
// Participation is proven without a Firebase service account: the ID token is
// verified against Google's public keys, then calls/{callId} is read with that
// same token, which the database rules only allow for the call's caller and
// receiver (see lib/shared.js). The uid comparison afterwards is a second
// check, not the only one.
//
// The channel name comes from the database and the Agora uid is derived from
// the verified Firebase uid. Neither is accepted from the client, so a
// participant cannot mint a token for another channel or impersonate the other
// party's uid.
//
// The App Certificate lives only in this server's environment and is never
// sent to the app: a certificate shipped in an APK can be extracted and used
// to mint tokens for any channel.

import agoraToken from 'agora-token';

import {
  HttpError,
  TERMINAL_STATUSES,
  bearerToken,
  parseBody,
  parseCallId,
  readCallAsUser,
  readFirebaseConfig,
  sendError,
  verifyFirebaseUser,
} from '../lib/shared.js';

const { RtcTokenBuilder, RtcRole } = agoraToken;

/// Tokens outlive any realistic call setup; the app renews before expiry
/// for long calls via Agora's onTokenPrivilegeWillExpire callback.
const TOKEN_TTL_SECONDS = 3600;

/// Characters Agora accepts in a channel name, per its token builder docs.
const CHANNEL_PATTERN = /^[A-Za-z0-9 !#$%&()+\-:;<=.>?@[\]^_{|}~,]{1,64}$/;

export default async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');

  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed.' });
  }

  try {
    const agora = readAgoraConfig();
    const { projectId, databaseUrl } = readFirebaseConfig();
    const idToken = bearerToken(req);
    const uid = await verifyFirebaseUser(idToken, projectId);
    const callId = parseCallId(parseBody(req.body));
    const call = await readCallAsUser(databaseUrl, callId, idToken);

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
      agora.appId,
      agora.appCertificate,
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
    return sendError(res, error, 'Could not issue a call token.');
  }
}

function readAgoraConfig() {
  const appId = process.env.AGORA_APP_ID;
  const appCertificate = process.env.AGORA_APP_CERTIFICATE;
  if (!appId || !appCertificate) {
    // Logged with names only, never values.
    console.error('token-server: missing AGORA_APP_ID or AGORA_APP_CERTIFICATE');
    throw new HttpError(500, 'The call service is not configured.');
  }
  return { appId, appCertificate };
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
