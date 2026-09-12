import { describe, expect, it } from "vitest";
import {
  base64urlToBytes,
  bytesToBase64url,
  classifyFailure,
  disableAppLock,
  enableAppLock,
  lockPhase,
  RELOCK_GRACE_MS,
  resumePhase,
  resetAppLock,
  verifyAppLock,
  type CredentialsLike,
  type LockStore,
} from "./appLock";

/** In-memory stand-in for localStorage. */
function memoryStore(initial: Record<string, string> = {}): LockStore & { data: Record<string, string> } {
  const data = { ...initial };
  return {
    data,
    get: (k) => data[k] ?? null,
    set: (k, v) => { data[k] = v; },
    remove: (k) => { delete data[k]; },
  };
}

const KEY_ENABLED = "ft.appLock";
const KEY_CREDENTIAL = "ft.appLockCredentialId";

const rawId = new Uint8Array([1, 2, 3, 250, 251, 252]).buffer;

/** Authenticator that always says yes. */
const willAllow: CredentialsLike = {
  create: async () => ({ rawId, type: "public-key" }) as unknown as Credential,
  get: async () => ({ rawId, type: "public-key" }) as unknown as Credential,
};

/** Authenticator that behaves like a dismissed Face ID sheet. */
const willRefuse = (name = "NotAllowedError"): CredentialsLike => {
  const fail = async () => {
    const e = new Error("refused");
    e.name = name;
    throw e;
  };
  return { create: fail, get: fail };
};

const supported = async () => ({ supported: true } as const);
const randomBytes = (n: number) => new Uint8Array(n).fill(7);
const deps = (credentials: CredentialsLike, store: LockStore) =>
  ({ credentials, store, randomBytes, support: supported });

describe("base64url round-trip", () => {
  it("survives bytes that plain base64 would escape", () => {
    // 250/251/252 are exactly the bytes that produce "+" and "/" in base64.
    // Those surviving a trip through localStorage is not worth risking.
    const encoded = bytesToBase64url(rawId);
    expect(encoded).not.toMatch(/[+/=]/);
    expect(Array.from(base64urlToBytes(encoded))).toEqual([1, 2, 3, 250, 251, 252]);
  });

  it("handles every unpadded length", () => {
    for (let len = 1; len <= 8; len++) {
      const bytes = new Uint8Array(len).map((_, i) => i * 31);
      const back = base64urlToBytes(bytesToBase64url(bytes.buffer));
      expect(Array.from(back)).toEqual(Array.from(bytes));
    }
  });
});

describe("failure classification", () => {
  it("reads a dismissed prompt as a cancel", () => {
    const e = new Error("x"); e.name = "NotAllowedError";
    expect(classifyFailure(e)).toBe("cancelled");
  });

  it("reads a timeout as a cancel, because the user did nothing either way", () => {
    const e = new Error("x"); e.name = "TimeoutError";
    expect(classifyFailure(e)).toBe("cancelled");
  });

  it("separates a browser refusal from a user refusal", () => {
    const e = new Error("x"); e.name = "SecurityError";
    expect(classifyFailure(e)).toBe("unsupported");
  });

  it("doesn't guess at anything it hasn't seen", () => {
    expect(classifyFailure(new Error("boom"))).toBe("unknown");
    expect(classifyFailure("not an error")).toBe("unknown");
  });
});

describe("enabling the lock", () => {
  it("persists only after the authenticator actually says yes", async () => {
    const store = memoryStore();
    const result = await enableAppLock(deps(willAllow, store));
    expect(result.ok).toBe(true);
    expect(store.data[KEY_ENABLED]).toBe("1");
    expect(store.data[KEY_CREDENTIAL]).toBeTruthy();
  });

  it("leaves the lock off when the prompt is dismissed", async () => {
    // The iOS toggle verified before persisting for this reason: a lock you
    // enabled but can't satisfy is a lock you're stuck behind.
    const store = memoryStore();
    const result = await enableAppLock(deps(willRefuse(), store));
    expect(result.ok).toBe(false);
    expect(result.failure).toBe("cancelled");
    expect(store.data[KEY_ENABLED]).toBeUndefined();
    expect(store.data[KEY_CREDENTIAL]).toBeUndefined();
  });

  it("refuses on a browser that can't do it, without touching storage", async () => {
    const store = memoryStore();
    const result = await enableAppLock({
      credentials: willAllow,
      store,
      randomBytes,
      support: async () => ({ supported: false, reason: "Needs HTTPS." }),
    });
    expect(result.ok).toBe(false);
    expect(result.detail).toBe("Needs HTTPS.");
    expect(store.data[KEY_ENABLED]).toBeUndefined();
  });
});

describe("unlocking", () => {
  it("passes the stored credential id back to the authenticator", async () => {
    const store = memoryStore();
    await enableAppLock(deps(willAllow, store));

    let requested: string | undefined;
    const spy: CredentialsLike = {
      create: willAllow.create,
      get: async (options) => {
        const allowed = options?.publicKey?.allowCredentials?.[0];
        requested = bytesToBase64url(allowed!.id as ArrayBuffer);
        return { rawId, type: "public-key" } as unknown as Credential;
      },
    };

    const result = await verifyAppLock(deps(spy, store));
    expect(result.ok).toBe(true);
    expect(requested).toBe(store.data[KEY_CREDENTIAL]);
  });

  it("reports a missing credential rather than prompting for nothing", async () => {
    // Cleared passkeys, a restored backup, a new device — the flag can outlive
    // the credential, and prompting with an empty allowlist just hangs.
    const store = memoryStore({ [KEY_ENABLED]: "1" });
    const result = await verifyAppLock(deps(willAllow, store));
    expect(result.ok).toBe(false);
    expect(result.failure).toBe("noCredential");
  });

  it("stays locked when the prompt is dismissed", async () => {
    const store = memoryStore();
    await enableAppLock(deps(willAllow, store));
    const result = await verifyAppLock(deps(willRefuse(), store));
    expect(result.ok).toBe(false);
    expect(result.failure).toBe("cancelled");
    // Still enrolled — a cancel must not quietly turn the lock off.
    expect(store.data[KEY_ENABLED]).toBe("1");
  });
});

describe("disabling the lock", () => {
  it("needs an unlock first", async () => {
    const store = memoryStore();
    await enableAppLock(deps(willAllow, store));
    const result = await disableAppLock(deps(willRefuse(), store));
    expect(result.ok).toBe(false);
    expect(store.data[KEY_ENABLED]).toBe("1");
  });

  it("clears both keys once verified", async () => {
    const store = memoryStore();
    await enableAppLock(deps(willAllow, store));
    const result = await disableAppLock(deps(willAllow, store));
    expect(result.ok).toBe(true);
    expect(store.data[KEY_ENABLED]).toBeUndefined();
    expect(store.data[KEY_CREDENTIAL]).toBeUndefined();
  });

  it("still turns off when the credential is already gone", async () => {
    // Otherwise the one state you can't unlock from is also the one state you
    // can't switch off from.
    const store = memoryStore({ [KEY_ENABLED]: "1" });
    const result = await disableAppLock(deps(willAllow, store));
    expect(result.ok).toBe(true);
    expect(store.data[KEY_ENABLED]).toBeUndefined();
  });

  it("resets without touching anything but its own keys", () => {
    const store = memoryStore({
      [KEY_ENABLED]: "1", [KEY_CREDENTIAL]: "abc", "ft.serverUrl": "https://example.workers.dev",
    });
    resetAppLock({ store });
    expect(store.data[KEY_ENABLED]).toBeUndefined();
    expect(store.data[KEY_CREDENTIAL]).toBeUndefined();
    expect(store.data["ft.serverUrl"]).toBe("https://example.workers.dev");
  });
});

describe("lock phase", () => {
  const now = 1_700_000_000_000;

  it("is open while the lock is off, however long the app was away", () => {
    expect(lockPhase({ enabled: false, hiddenAt: now - 86_400_000, now })).toBe("open");
  });

  it("is open while the app is on screen", () => {
    expect(lockPhase({ enabled: true, hiddenAt: undefined, now })).toBe("open");
  });

  it("curtains a quick trip to the SMS app instead of re-locking", () => {
    // Flipping out to copy an OTP and straight back is normal use of this app.
    // Demanding Face ID for it is how a lock gets turned off for good.
    expect(lockPhase({ enabled: true, hiddenAt: now - 3_000, now })).toBe("curtained");
  });

  it("locks once the grace has elapsed", () => {
    expect(lockPhase({ enabled: true, hiddenAt: now - RELOCK_GRACE_MS, now })).toBe("locked");
    expect(lockPhase({ enabled: true, hiddenAt: now - RELOCK_GRACE_MS - 1, now })).toBe("locked");
  });

  it("honours a caller-supplied grace", () => {
    expect(lockPhase({ enabled: true, hiddenAt: now - 5_000, now, graceMs: 1_000 })).toBe("locked");
    expect(lockPhase({ enabled: true, hiddenAt: now - 5_000, now, graceMs: 60_000 })).toBe("curtained");
  });
});

describe("coming back", () => {
  const now = 1_700_000_000_000;

  it("lifts the curtain after a short trip instead of carrying it into a visible app", () => {
    // The first cut used lockPhase here and left the app permanently blurred
    // after any quick flip out and back.
    expect(resumePhase({ enabled: true, hiddenAt: now - 3_000, now })).toBe("open");
  });

  it("demands a biometric after a long one", () => {
    expect(resumePhase({ enabled: true, hiddenAt: now - RELOCK_GRACE_MS, now })).toBe("locked");
  });

  it("is open when the lock is off", () => {
    expect(resumePhase({ enabled: false, hiddenAt: now - 86_400_000, now })).toBe("open");
  });
});
