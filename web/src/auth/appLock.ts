/**
 * App lock — the web stand-in for the Swift build's Face ID gate.
 *
 * WebAuthn with a platform authenticator is what reaches Face ID / Touch ID
 * from a browser, so that's what this uses. Be clear about what it buys:
 *
 *   - It guards a SCREEN, not the data. IndexedDB stays readable to anything
 *     that can open devtools on an unlocked device. `LAContext` had exactly the
 *     same property in the iOS build — the file protection there was the OS's,
 *     not the lock's — it's just less obvious on the web.
 *   - There is no server, so nothing verifies the assertion signature. A
 *     determined attacker bypasses this from the console. It stops the person
 *     who picks up your unlocked phone, which is the threat that actually
 *     happens.
 *
 * Being honest about that is the reason the recovery path below exists at all:
 * a finance app you can permanently lock yourself out of, with no account and
 * no reset email, would be worse than one whose lock is admittedly a screen.
 */

const KEY_ENABLED = "ft.appLock";
const KEY_CREDENTIAL = "ft.appLockCredentialId";

/** How long the app can be backgrounded before it demands a re-unlock. */
export const RELOCK_GRACE_MS = 30_000;

/** Consecutive failures before the recovery affordance appears. */
export const RECOVERY_AFTER_FAILURES = 3;

// ── storage ──────────────────────────────────────────────────────────────────

/** Same shape as localStorage, injectable so the tests don't need a DOM. */
export interface LockStore {
  get(key: string): string | null;
  set(key: string, value: string): void;
  remove(key: string): void;
}

const localStore: LockStore = {
  get: (k) => { try { return localStorage.getItem(k); } catch { return null; } },
  set: (k, v) => { try { localStorage.setItem(k, v); } catch { /* private mode / quota */ } },
  remove: (k) => { try { localStorage.removeItem(k); } catch { /* ignore */ } },
};

export const lockPrefs = {
  get enabled(): boolean { return localStore.get(KEY_ENABLED) === "1"; },
  /** The credential this device enrolled. Its absence means the lock can't be enforced. */
  get credentialId(): string | null { return localStore.get(KEY_CREDENTIAL); },
};

// ── base64url ────────────────────────────────────────────────────────────────
//
// WebAuthn hands back ArrayBuffers and wants them back as ArrayBuffers, but
// localStorage only holds strings. base64url rather than plain base64 because
// the credential id is also a URL-safe identifier by convention, and `+`/`/`
// surviving a round-trip through anything else is not worth the risk.

export function bytesToBase64url(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function base64urlToBytes(value: string): Uint8Array<ArrayBuffer> {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/")
    .padEnd(Math.ceil(value.length / 4) * 4, "=");
  const binary = atob(padded);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

// ── support detection ────────────────────────────────────────────────────────

export type LockSupport =
  | { supported: true }
  | { supported: false; reason: string };

/**
 * Whether this browser can gate the app behind a platform authenticator.
 *
 * A bare "not available" leaves the user with nothing to act on, so each
 * negative case says which one it is — the same reasoning as `pushSupport()`.
 */
export async function lockSupport(): Promise<LockSupport> {
  if (typeof window === "undefined") return { supported: false, reason: "Not running in a browser." };
  if (!window.isSecureContext) {
    return { supported: false, reason: "Needs HTTPS. The lock is unavailable over plain HTTP." };
  }
  if (!("PublicKeyCredential" in window) || !navigator.credentials) {
    return { supported: false, reason: "This browser has no WebAuthn support, so it can't reach Face ID or a fingerprint sensor." };
  }
  const available = await PublicKeyCredential
    .isUserVerifyingPlatformAuthenticatorAvailable()
    .catch(() => false);
  if (!available) {
    return {
      supported: false,
      reason: "No device unlock is set up here. Turn on Face ID, Touch ID, or a device passcode first.",
    };
  }
  return { supported: true };
}

// ── failure classification ───────────────────────────────────────────────────

export type LockFailure = "cancelled" | "unsupported" | "noCredential" | "unknown";

/**
 * Why an enrol or unlock didn't happen.
 *
 * Note what this deliberately does NOT try to do: tell "user cancelled" apart
 * from "the credential is gone". Safari reports both as `NotAllowedError`, and
 * guessing would produce a recovery prompt on every accidental cancel. Repeated
 * failure is what surfaces recovery instead — see RECOVERY_AFTER_FAILURES.
 */
export function classifyFailure(error: unknown): LockFailure {
  if (!(error instanceof Error)) return "unknown";
  switch (error.name) {
    case "NotAllowedError":
    case "AbortError":
    case "TimeoutError":
      return "cancelled";
    case "NotSupportedError":
    case "SecurityError":
      return "unsupported";
    case "InvalidStateError":
      return "noCredential";
    default:
      return "unknown";
  }
}

export function failureMessage(failure: LockFailure): string {
  switch (failure) {
    case "cancelled":
      return "Unlock was cancelled.";
    case "unsupported":
      return "This browser refused the request. The lock can't be used here.";
    case "noCredential":
      return "This device's saved unlock is no longer valid.";
    default:
      return "Something went wrong. Try again.";
  }
}

// ── enrol / verify ───────────────────────────────────────────────────────────

/** Minimal slice of `navigator.credentials` — a full stub of it isn't worth writing. */
export type CredentialsLike = Pick<CredentialsContainer, "create" | "get">;

export interface LockDeps {
  credentials?: CredentialsLike;
  store?: LockStore;
  randomBytes?: (length: number) => Uint8Array<ArrayBuffer>;
  /** Overridable so the enrol path is testable without faking a whole DOM. */
  support?: () => Promise<LockSupport>;
}

// Typed as ArrayBuffer-backed, not ArrayBufferLike: WebAuthn's BufferSource
// excludes SharedArrayBuffer, and the bare `Uint8Array` alias includes it.
const defaultRandom = (length: number): Uint8Array<ArrayBuffer> =>
  crypto.getRandomValues(new Uint8Array(length));

export interface LockResult {
  ok: boolean;
  failure?: LockFailure;
  detail: string;
}

/**
 * Register this device's authenticator and turn the lock on.
 *
 * The toggle only persists once the user has actually authenticated — the same
 * guard the iOS build used, and for the same reason: a lock you enabled but
 * can't satisfy is a lock you're stuck behind.
 *
 * Must be called from a user gesture. Browsers ignore a WebAuthn prompt that
 * isn't tied to one, and some treat the dismissal as permanent.
 */
export async function enableAppLock(deps: LockDeps = {}): Promise<LockResult> {
  const creds = deps.credentials ?? navigator.credentials;
  const store = deps.store ?? localStore;
  const random = deps.randomBytes ?? defaultRandom;

  const support = await (deps.support ?? lockSupport)();
  if (!support.supported) return { ok: false, failure: "unsupported", detail: support.reason };

  try {
    const credential = (await creds.create({
      publicKey: {
        challenge: random(32),
        rp: { name: "FinanceTracker" },
        // Not an account, just a handle the authenticator can label. Random so
        // nothing identifying about the user ends up in the passkey list.
        user: { id: random(16), name: "FinanceTracker", displayName: "FinanceTracker" },
        pubKeyCredParams: [
          { type: "public-key", alg: -7 },   // ES256
          { type: "public-key", alg: -257 }, // RS256
        ],
        authenticatorSelection: {
          // Platform only: a roaming security key would technically work, but
          // the point here is the biometric already on the phone.
          authenticatorAttachment: "platform",
          userVerification: "required",
          residentKey: "discouraged",
        },
        // Nothing verifies attestation without a server, so don't ask for it —
        // requesting attestation triggers an extra consent prompt on some
        // platforms for information that would go straight in the bin.
        attestation: "none",
        timeout: 60_000,
      },
    })) as PublicKeyCredential | null;

    if (!credential) return { ok: false, failure: "unknown", detail: failureMessage("unknown") };

    store.set(KEY_CREDENTIAL, bytesToBase64url(credential.rawId));
    store.set(KEY_ENABLED, "1");
    return { ok: true, detail: "App lock is on. It'll ask when you open the app." };
  } catch (error) {
    const failure = classifyFailure(error);
    return { ok: false, failure, detail: failureMessage(failure) };
  }
}

/**
 * Ask the authenticator to confirm the user is present.
 *
 * The assertion is not verified against anything — there's no server and no
 * stored public key to check it with. What's being consumed here is the
 * platform's user-verification gate, not a cryptographic proof.
 */
export async function verifyAppLock(deps: LockDeps = {}): Promise<LockResult> {
  const creds = deps.credentials ?? navigator.credentials;
  const store = deps.store ?? localStore;
  const random = deps.randomBytes ?? defaultRandom;

  const credentialId = store.get(KEY_CREDENTIAL);
  if (!credentialId) {
    return { ok: false, failure: "noCredential", detail: failureMessage("noCredential") };
  }

  try {
    const assertion = await creds.get({
      publicKey: {
        challenge: random(32),
        allowCredentials: [{
          type: "public-key",
          id: base64urlToBytes(credentialId),
          transports: ["internal"],
        }],
        userVerification: "required",
        timeout: 60_000,
      },
    });
    if (!assertion) return { ok: false, failure: "unknown", detail: failureMessage("unknown") };
    return { ok: true, detail: "Unlocked." };
  } catch (error) {
    const failure = classifyFailure(error);
    return { ok: false, failure, detail: failureMessage(failure) };
  }
}

/**
 * Turn the lock off. Requires an unlock first, so someone holding the phone
 * can't quietly disable it — the iOS toggle verified in both directions too.
 */
export async function disableAppLock(deps: LockDeps = {}): Promise<LockResult> {
  const store = deps.store ?? localStore;
  const result = await verifyAppLock(deps);
  if (!result.ok && result.failure !== "noCredential") return result;

  store.remove(KEY_ENABLED);
  store.remove(KEY_CREDENTIAL);
  return { ok: true, detail: "App lock is off." };
}

/**
 * The escape hatch, reached only after repeated failures.
 *
 * Yes, this means anyone holding the device can eventually get in. That is
 * already true — the data is readable without the app at all — and the
 * alternative is a user permanently locked out of their own ledger by a
 * cleared passkey, a restored backup, or a new phone. Data is never touched.
 */
export function resetAppLock(deps: LockDeps = {}): void {
  const store = deps.store ?? localStore;
  store.remove(KEY_ENABLED);
  store.remove(KEY_CREDENTIAL);
}

// ── lock state machine ───────────────────────────────────────────────────────

export type LockPhase =
  /** Lock is off, or already satisfied for this session. */
  | "open"
  /** Backgrounded briefly — content is curtained but not re-locked yet. */
  | "curtained"
  /** Needs an unlock before anything is shown. */
  | "locked";

export interface LockStateInput {
  enabled: boolean;
  /** When the app was last hidden, or undefined if it's visible. */
  hiddenAt: number | undefined;
  now: number;
  graceMs?: number;
}

/**
 * What to show while the app is AWAY, given how long it's been away.
 *
 * The Swift app re-locked the instant it backgrounded. That's harsher than it
 * needs to be on the web, where flipping out to the SMS app to copy an OTP and
 * straight back is a normal part of using this thing — so a short absence draws
 * a curtain (which is also what the app switcher screenshots) and anything
 * longer demands the biometric again.
 */
export function lockPhase(input: LockStateInput): LockPhase {
  const { enabled, hiddenAt, now, graceMs = RELOCK_GRACE_MS } = input;
  if (!enabled) return "open";
  if (hiddenAt === undefined) return "open";
  return now - hiddenAt >= graceMs ? "locked" : "curtained";
}

/**
 * What to show once the app is BACK on screen.
 *
 * The distinction matters: "curtained" is a state you can only be in while
 * hidden, so a short trip has to resolve to `open` here rather than carrying
 * the curtain back into a visible app — which is exactly the bug the first cut
 * of this shipped with.
 */
export function resumePhase(input: LockStateInput): "open" | "locked" {
  return lockPhase(input) === "locked" ? "locked" : "open";
}
