/**
 * Web Push from a Cloudflare Worker, using WebCrypto only.
 *
 * There's no `web-push` npm package here — that one needs Node crypto. This
 * implements the two specs directly:
 *
 *   RFC 8292 (VAPID)   — an ES256 JWT identifying the sender, so the push
 *                        service will accept the request.
 *   RFC 8291 (aes128gcm) — payload encryption. The push service relays bytes it
 *                        cannot read; only the browser holds the key.
 *
 * This matters for iOS: an installed PWA can receive Web Push (16.4+) but
 * cannot schedule a local notification, so every reminder the Swift app fired
 * with UNCalendarNotificationTrigger has to arrive this way instead.
 */

export interface PushSubscription {
  endpoint: string;
  keys: { p256dh: string; auth: string };
}

export interface VapidKeys {
  /** base64url, uncompressed P-256 point (65 bytes, 0x04-prefixed). */
  publicKey: string;
  /** base64url, raw 32-byte private scalar. */
  privateKey: string;
  /** "mailto:you@example.com" — required by the spec, used only for contact. */
  subject: string;
}

// ── base64url ────────────────────────────────────────────────────────────────

export function b64urlDecode(s: string): Uint8Array {
  const padded = s.replace(/-/g, "+").replace(/_/g, "/")
    .padEnd(Math.ceil(s.length / 4) * 4, "=");
  const bin = atob(padded);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function b64urlEncode(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

const utf8 = (s: string) => new TextEncoder().encode(s);

/**
 * `@cloudflare/workers-types` models a few WebCrypto corners differently from
 * the spec the runtime actually implements: `exportKey` is typed as a union
 * rather than per-format, and ECDH's `public` key field is spelled `$public`.
 * These two shims keep the divergence in one place instead of scattering casts.
 */
type DeriveBitsAlgorithm = Parameters<SubtleCrypto["deriveBits"]>[0];

const exportRaw = async (key: CryptoKey): Promise<ArrayBuffer> =>
  await crypto.subtle.exportKey("raw", key) as ArrayBuffer;

const ecdhWith = (publicKey: CryptoKey) =>
  ({ name: "ECDH", public: publicKey } as unknown as DeriveBitsAlgorithm);

function concat(...parts: Uint8Array[]): Uint8Array {
  const total = parts.reduce((n, p) => n + p.length, 0);
  const out = new Uint8Array(total);
  let at = 0;
  for (const p of parts) { out.set(p, at); at += p.length; }
  return out;
}

// ── HKDF (RFC 5869), the single-block form the push spec uses ────────────────

async function hmac(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  const k = await crypto.subtle.importKey(
    "raw", key, { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  return new Uint8Array(await crypto.subtle.sign("HMAC", k, data));
}

/** Every derivation here fits in one HMAC block, so the counter is always 0x01. */
async function hkdf(
  salt: Uint8Array, ikm: Uint8Array, info: Uint8Array, length: number,
): Promise<Uint8Array> {
  const prk = await hmac(salt, ikm);
  const okm = await hmac(prk, concat(info, new Uint8Array([1])));
  return okm.slice(0, length);
}

// ── VAPID (RFC 8292) ─────────────────────────────────────────────────────────

/**
 * A P-256 private key in PKCS#8, assembled around the raw 32-byte scalar.
 *
 * WebCrypto won't import a bare scalar, and the fixed ASN.1 prefix for
 * "EC private key, prime256v1" is the standard way around that.
 */
function pkcs8FromRawP256(privateScalar: Uint8Array, publicKey: Uint8Array): Uint8Array {
  const prefix = new Uint8Array([
    0x30, 0x81, 0x87, 0x02, 0x01, 0x00, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86,
    0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d,
    0x03, 0x01, 0x07, 0x04, 0x6d, 0x30, 0x6b, 0x02, 0x01, 0x01, 0x04, 0x20,
  ]);
  const middle = new Uint8Array([0xa1, 0x44, 0x03, 0x42, 0x00]);
  return concat(prefix, privateScalar, middle, publicKey);
}

async function importVapidSigningKey(keys: VapidKeys): Promise<CryptoKey> {
  const pkcs8 = pkcs8FromRawP256(
    b64urlDecode(keys.privateKey),
    b64urlDecode(keys.publicKey),
  );
  return crypto.subtle.importKey(
    "pkcs8", pkcs8, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"],
  );
}

/** Signed JWT proving who is sending, scoped to one push service origin. */
export async function vapidToken(audience: string, keys: VapidKeys): Promise<string> {
  const header = b64urlEncode(utf8(JSON.stringify({ typ: "JWT", alg: "ES256" })));
  const claims = b64urlEncode(utf8(JSON.stringify({
    aud: audience,
    // Push services reject anything more than 24h out; 12h leaves slack.
    exp: Math.floor(Date.now() / 1000) + 12 * 60 * 60,
    sub: keys.subject,
  })));
  const signingInput = `${header}.${claims}`;
  const key = await importVapidSigningKey(keys);
  // WebCrypto emits the raw r||s form ES256 wants — no DER unwrapping needed.
  const sig = new Uint8Array(await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, key, utf8(signingInput),
  ));
  return `${signingInput}.${b64urlEncode(sig)}`;
}

// ── payload encryption (RFC 8291) ────────────────────────────────────────────

const RECORD_SIZE = 4096;

/**
 * Encrypt a payload to a subscription's key pair.
 *
 * The push service is an untrusted relay: it sees the endpoint and the byte
 * count, never the content.
 */
export async function encryptPayload(
  sub: PushSubscription,
  plaintext: string,
): Promise<Uint8Array> {
  const uaPublic = b64urlDecode(sub.keys.p256dh);
  const authSecret = b64urlDecode(sub.keys.auth);

  // Ephemeral sender key — a fresh one per message, as the spec requires.
  const asKeyPair = await crypto.subtle.generateKey(
    { name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"],
  ) as CryptoKeyPair;
  const asPublic = new Uint8Array(await exportRaw(asKeyPair.publicKey));

  const uaKey = await crypto.subtle.importKey(
    "raw", uaPublic, { name: "ECDH", namedCurve: "P-256" }, false, [],
  );
  const shared = new Uint8Array(await crypto.subtle.deriveBits(
    ecdhWith(uaKey), asKeyPair.privateKey, 256,
  ));

  // The key derivation binds both public keys, so a captured message can't be
  // replayed against a different subscription.
  const keyInfo = concat(utf8("WebPush: info\0"), uaPublic, asPublic);
  const ikm = await hkdf(authSecret, shared, keyInfo, 32);

  const salt = crypto.getRandomValues(new Uint8Array(16));
  const cek = await hkdf(salt, ikm, utf8("Content-Encoding: aes128gcm\0"), 16);
  const nonce = await hkdf(salt, ikm, utf8("Content-Encoding: nonce\0"), 12);

  const aesKey = await crypto.subtle.importKey("raw", cek, "AES-GCM", false, ["encrypt"]);
  // 0x02 is the last-record padding delimiter; everything fits in one record.
  const body = concat(utf8(plaintext), new Uint8Array([2]));
  const ciphertext = new Uint8Array(await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce }, aesKey, body,
  ));

  const rs = new Uint8Array(4);
  new DataView(rs.buffer).setUint32(0, RECORD_SIZE, false);
  const header = concat(salt, rs, new Uint8Array([asPublic.length]), asPublic);
  return concat(header, ciphertext);
}

// ── sending ──────────────────────────────────────────────────────────────────

export interface PushResult {
  endpoint: string;
  status: number;
  /** True when the push service says this subscription is dead and should be dropped. */
  gone: boolean;
}

export async function sendPush(
  sub: PushSubscription,
  payload: unknown,
  keys: VapidKeys,
  ttlSeconds = 12 * 60 * 60,
): Promise<PushResult> {
  const audience = new URL(sub.endpoint).origin;
  const [token, body] = await Promise.all([
    vapidToken(audience, keys),
    encryptPayload(sub, JSON.stringify(payload)),
  ]);

  const response = await fetch(sub.endpoint, {
    method: "POST",
    headers: {
      Authorization: `vapid t=${token}, k=${keys.publicKey}`,
      "Content-Encoding": "aes128gcm",
      "Content-Type": "application/octet-stream",
      TTL: String(ttlSeconds),
      Urgency: "normal",
    },
    body,
  });

  // 404/410 mean the user uninstalled or cleared the site — the row is dead.
  return {
    endpoint: sub.endpoint,
    status: response.status,
    gone: response.status === 404 || response.status === 410,
  };
}

/**
 * Generate a VAPID key pair. Run once, store both halves as Worker secrets, and
 * ship the public half to the client.
 */
export async function generateVapidKeys(subject: string): Promise<VapidKeys> {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"],
  ) as CryptoKeyPair;
  const publicKey = new Uint8Array(await exportRaw(pair.publicKey));
  const jwk = await crypto.subtle.exportKey("jwk", pair.privateKey) as JsonWebKey;
  return {
    publicKey: b64urlEncode(publicKey),
    privateKey: jwk.d!,
    subject,
  };
}
