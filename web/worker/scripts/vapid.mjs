#!/usr/bin/env node
/**
 * Generate a VAPID key pair for Web Push.
 *
 * Run once. The private key goes into the Worker as a secret and never leaves
 * it; the public key goes in as a secret too (the Worker serves it to the
 * browser, which needs it to subscribe).
 *
 *   node scripts/vapid.mjs
 */
import { webcrypto } from "node:crypto";

const b64url = (bytes) =>
  Buffer.from(bytes).toString("base64")
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

const pair = await webcrypto.subtle.generateKey(
  { name: "ECDH", namedCurve: "P-256" },
  true,
  ["deriveBits"],
);

const publicKey = b64url(await webcrypto.subtle.exportKey("raw", pair.publicKey));
const { d: privateKey } = await webcrypto.subtle.exportKey("jwk", pair.privateKey);

console.log(`
VAPID key pair generated. Set all three as Worker secrets:

  npx wrangler secret put VAPID_PUBLIC_KEY
  ${publicKey}

  npx wrangler secret put VAPID_PRIVATE_KEY
  ${privateKey}

  npx wrangler secret put VAPID_SUBJECT
  mailto:you@example.com

Keep the private key secret. Regenerating the pair invalidates every existing
push subscription — each device has to turn notifications on again.
`);
