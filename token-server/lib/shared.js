// Checks shared by every ConnectCall endpoint.
//
// Both /api/token and /api/notify answer the same two questions before doing
// anything: who is asking (a verified Firebase ID token), and are they a
// participant in the call they name (proved by reading the call with their
// own token, which the database rules only allow for its two participants).

import { createRemoteJWKSet, jwtVerify } from 'jose';

/// Realtime Database push keys are 20 characters of [A-Za-z0-9_-]. Anything
/// else is rejected before it can reach a database path, so input like
/// "../users" cannot walk the tree.
export const CALL_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

/// A call in any of these states is over.
export const TERMINAL_STATUSES = new Set([
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

export class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

/// Project id and database URL, required by every endpoint.
export function readFirebaseConfig() {
  const projectId = process.env.FIREBASE_PROJECT_ID;
  const databaseUrl = process.env.FIREBASE_DATABASE_URL?.replace(/\/+$/, '');
  if (!projectId || !databaseUrl) {
    console.error('connectcall: missing FIREBASE_PROJECT_ID or FIREBASE_DATABASE_URL');
    throw new HttpError(500, 'The call service is not configured.');
  }
  return { projectId, databaseUrl };
}

export function bearerToken(req) {
  const header = req.headers.authorization ?? '';
  const match = /^Bearer\s+(.+)$/i.exec(header);
  if (!match) throw new HttpError(401, 'Missing sign-in credentials.');
  return match[1].trim();
}

export async function verifyFirebaseUser(idToken, projectId) {
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

/// The request body as an object, whether Vercel already parsed it or not.
export function parseBody(body) {
  if (typeof body !== 'string') return body ?? {};
  try {
    return JSON.parse(body);
  } catch {
    throw new HttpError(400, 'Request body must be JSON.');
  }
}

export function parseCallId(body) {
  const callId = body?.callId;
  if (typeof callId !== 'string' || !CALL_ID_PATTERN.test(callId)) {
    throw new HttpError(400, 'A valid callId is required.');
  }
  return callId;
}

/// Reads calls/{callId} as the requester. Succeeds only for the call's two
/// participants, because that is what the database rules allow.
export async function readCallAsUser(databaseUrl, callId, idToken) {
  const url = `${databaseUrl}/calls/${callId}.json?auth=${encodeURIComponent(idToken)}`;

  let response;
  try {
    response = await fetch(url);
  } catch {
    throw new HttpError(502, 'Could not reach the call database.');
  }

  // The rules deny reads to non-participants, and also to calls that do not
  // exist (the rule compares against callerId, which is null for a missing
  // node). Both are reported the same way, so an endpoint cannot be used to
  // probe which call ids exist.
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

/// Sends an error response. Expected failures carry their own status and
/// message; anything unexpected is logged server-side only, and the client
/// gets a generic message, never a stack trace or configuration detail.
export function sendError(res, error, fallbackMessage) {
  if (error instanceof HttpError) {
    return res.status(error.status).json({ error: error.message });
  }
  console.error('connectcall: unexpected error', error);
  return res.status(500).json({ error: fallbackMessage });
}
