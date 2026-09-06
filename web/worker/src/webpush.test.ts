import { describe, expect, it } from "vitest";
import { webcrypto } from "node:crypto";
import { b64urlDecode, b64urlEncode, encryptPayload, generateVapidKeys, vapidToken } from "./webpush";

/**
 * There is no push service to test against, so these tests play the receiver.
 *
 * The encryption is implemented from RFC 8291 by hand (the `web-push` package
 * needs Node crypto and won't run in a Worker), and a mistake in it is
 * invisible — the push service accepts the bytes and the phone silently shows
 * nothing. So the test decrypts what we encrypt, exactly as a browser would.
 */

// The Worker runtime has WebCrypto as a global; Node needs it wired up. Typed
// loosely because the workers-types Crypto and Node's don't line up exactly.
const g = globalThis as unknown as { crypto?: unknown };
g.crypto ??= webcrypto;

type DeriveBitsAlgorithm = Parameters<SubtleCrypto["deriveBits"]>[0];

const exportRaw = async (key: CryptoKey): Promise<ArrayBuffer> =>
  await crypto.subtle.exportKey("raw", key) as ArrayBuffer;

const ecdhWith = (publicKey: CryptoKey) =>
  ({ name: "ECDH", public: publicKey } as unknown as DeriveBitsAlgorithm);

const utf8 = (s: string) => new TextEncoder().encode(s);

function concat(...parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) { out.set(p, at); at += p.length; }
  return out;
}

async function hmac(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  const k = await crypto.subtle.importKey("raw", key, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", k, data));
}

async function hkdf(salt: Uint8Array, ikm: Uint8Array, info: Uint8Array, length: number) {
  const prk = await hmac(salt, ikm);
  return (await hmac(prk, concat(info, new Uint8Array([1])))).slice(0, length);
}

/** A browser-side subscription: an ECDH key pair plus a random auth secret. */
async function makeSubscription() {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"],
  ) as CryptoKeyPair;
  const p256dh = new Uint8Array(await exportRaw(pair.publicKey));
  const auth = crypto.getRandomValues(new Uint8Array(16));
  return {
    subscription: {
      endpoint: "https://push.example.com/v1/abc",
      keys: { p256dh: b64urlEncode(p256dh), auth: b64urlEncode(auth) },
    },
    privateKey: pair.privateKey,
    p256dh,
    auth,
  };
}

/** Undo encryptPayload the way a browser does, following RFC 8291 §3.4. */
async function decrypt(
  body: Uint8Array,
  privateKey: CryptoKey,
  uaPublic: Uint8Array,
  authSecret: Uint8Array,
): Promise<string> {
  const salt = body.slice(0, 16);
  const idlen = body[20]!;
  const asPublic = body.slice(21, 21 + idlen);
  const ciphertext = body.slice(21 + idlen);

  const asKey = await crypto.subtle.importKey(
    "raw", asPublic, { name: "ECDH", namedCurve: "P-256" }, false, [],
  );
  const shared = new Uint8Array(await crypto.subtle.deriveBits(
    ecdhWith(asKey), privateKey, 256,
  ));

  const ikm = await hkdf(
    authSecret, shared, concat(utf8("WebPush: info\0"), uaPublic, asPublic), 32,
  );
  const cek = await hkdf(salt, ikm, utf8("Content-Encoding: aes128gcm\0"), 16);
  const nonce = await hkdf(salt, ikm, utf8("Content-Encoding: nonce\0"), 12);

  const key = await crypto.subtle.importKey("raw", cek, "AES-GCM", false, ["decrypt"]);
  const plain = new Uint8Array(await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: nonce }, key, ciphertext,
  ));
  // Strip the 0x02 last-record padding delimiter.
  return new TextDecoder().decode(plain.slice(0, -1));
}

describe("base64url", () => {
  it("round-trips bytes, including ones needing padding", () => {
    for (const length of [1, 2, 3, 16, 32, 65]) {
      const bytes = crypto.getRandomValues(new Uint8Array(length));
      expect([...b64urlDecode(b64urlEncode(bytes))]).toEqual([...bytes]);
    }
  });

  it("emits no padding or URL-unsafe characters", () => {
    const encoded = b64urlEncode(new Uint8Array([251, 255, 190, 255]));
    expect(encoded).not.toMatch(/[+/=]/);
  });

  it("decodes what a browser subscription would send", () => {
    // A p256dh key is a 65-byte uncompressed point starting with 0x04.
    const key = b64urlEncode(concat(new Uint8Array([4]), crypto.getRandomValues(new Uint8Array(64))));
    const decoded = b64urlDecode(key);
    expect(decoded.length).toBe(65);
    expect(decoded[0]).toBe(4);
  });
});

describe("payload encryption", () => {
  it("produces a payload the subscription can decrypt", async () => {
    const { subscription, privateKey, p256dh, auth } = await makeSubscription();
    const message = JSON.stringify({ title: "Rent · ₹25,000", body: "Due tomorrow.", tag: "bill-rent" });

    const body = await encryptPayload(subscription, message);
    expect(await decrypt(body, privateKey, p256dh, auth)).toBe(message);
  });

  it("lays the header out as salt(16) | rs(4) | idlen(1) | key(65)", async () => {
    const { subscription } = await makeSubscription();
    const body = await encryptPayload(subscription, "hi");
    expect(new DataView(body.buffer, body.byteOffset).getUint32(16, false)).toBe(4096);
    expect(body[20]).toBe(65);
    expect(body[21]).toBe(4); // uncompressed point marker
  });

  it("uses a fresh ephemeral key and salt for every message", async () => {
    // Reusing either would let a captured message be replayed or correlated.
    const { subscription } = await makeSubscription();
    const a = await encryptPayload(subscription, "same text");
    const b = await encryptPayload(subscription, "same text");
    expect(b64urlEncode(a.slice(0, 16))).not.toBe(b64urlEncode(b.slice(0, 16)));
    expect(b64urlEncode(a.slice(21, 86))).not.toBe(b64urlEncode(b.slice(21, 86)));
  });

  it("cannot be decrypted with a different subscription's key", async () => {
    const mine = await makeSubscription();
    const theirs = await makeSubscription();
    const body = await encryptPayload(mine.subscription, "private");
    await expect(
      decrypt(body, theirs.privateKey, theirs.p256dh, theirs.auth),
    ).rejects.toThrow();
  });

  it("handles a payload with non-ASCII text", async () => {
    const { subscription, privateKey, p256dh, auth } = await makeSubscription();
    const message = "₹1,23,456 — bill payment due";
    const body = await encryptPayload(subscription, message);
    expect(await decrypt(body, privateKey, p256dh, auth)).toBe(message);
  });
});

describe("VAPID keys", () => {
  it("generates a 65-byte public point and a 32-byte private scalar", async () => {
    const keys = await generateVapidKeys("mailto:test@example.com");
    expect(b64urlDecode(keys.publicKey).length).toBe(65);
    expect(b64urlDecode(keys.privateKey).length).toBe(32);
    expect(keys.subject).toBe("mailto:test@example.com");
  });
});

describe("VAPID token", () => {
  /** Verify with the public half, the way a push service does. */
  async function verify(token: string, publicKey: string): Promise<boolean> {
    const [header, claims, signature] = token.split(".");
    const key = await crypto.subtle.importKey(
      "raw", b64urlDecode(publicKey), { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"],
    );
    return crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      b64urlDecode(signature!),
      utf8(`${header}.${claims}`),
    );
  }

  it("signs a token the matching public key verifies", async () => {
    // The private key is hand-assembled into PKCS#8 around a fixed ASN.1
    // prefix, since WebCrypto won't import a bare P-256 scalar. If that
    // assembly is wrong the push service just returns 401 with no explanation.
    const keys = await generateVapidKeys("mailto:me@example.com");
    const token = await vapidToken("https://push.example.com", keys);
    expect(await verify(token, keys.publicKey)).toBe(true);
  });

  it("carries the audience, subject and an expiry inside 24 hours", async () => {
    const keys = await generateVapidKeys("mailto:me@example.com");
    const token = await vapidToken("https://fcm.googleapis.com", keys);
    const [rawHeader, rawClaims] = token.split(".");

    const header = JSON.parse(new TextDecoder().decode(b64urlDecode(rawHeader!)));
    expect(header).toEqual({ typ: "JWT", alg: "ES256" });

    const claims = JSON.parse(new TextDecoder().decode(b64urlDecode(rawClaims!)));
    expect(claims.aud).toBe("https://fcm.googleapis.com");
    expect(claims.sub).toBe("mailto:me@example.com");
    // Push services reject anything further out than 24h.
    const hoursOut = (claims.exp - Date.now() / 1000) / 3600;
    expect(hoursOut).toBeGreaterThan(0);
    expect(hoursOut).toBeLessThan(24);
  });

  it("fails verification against a different key pair", async () => {
    const mine = await generateVapidKeys("mailto:me@example.com");
    const other = await generateVapidKeys("mailto:other@example.com");
    const token = await vapidToken("https://push.example.com", mine);
    expect(await verify(token, other.publicKey)).toBe(false);
  });
});
