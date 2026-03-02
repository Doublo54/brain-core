import { describe, expect, it } from "vitest";
import { chunkTelegramText, extractFloodWaitSeconds, isTransientSendError } from "./send-utils.js";

describe("telegramuser flood wait parsing", () => {
  it("parses FLOOD_WAIT error", () => {
    expect(extractFloodWaitSeconds(new Error("FLOOD_WAIT_17"))).toBe(17);
  });

  it("parses humanized wait error", () => {
    expect(extractFloodWaitSeconds(new Error("A wait of 8 seconds is required"))).toBe(8);
  });

  it("caps long waits", () => {
    expect(extractFloodWaitSeconds(new Error("FLOOD_WAIT_500"))).toBe(120);
  });

  it("returns null for unrelated errors", () => {
    expect(extractFloodWaitSeconds(new Error("network timeout"))).toBeNull();
  });
});

describe("telegramuser text chunking", () => {
  it("keeps short text as one chunk", () => {
    const chunks = chunkTelegramText("hello");
    expect(chunks).toEqual(["hello"]);
  });

  it("splits long text within telegram limit", () => {
    const input = "a".repeat(5000);
    const chunks = chunkTelegramText(input);
    expect(chunks.length).toBeGreaterThan(1);
    expect(chunks.every((c) => c.length <= 4096)).toBe(true);
    expect(chunks.join("").length).toBe(5000);
  });
});

describe("telegramuser transient send errors", () => {
  it("detects transient network errors", () => {
    expect(isTransientSendError(new Error("network timeout"))).toBe(true);
    expect(isTransientSendError(new Error("ECONNRESET"))).toBe(true);
  });

  it("ignores non-transient errors", () => {
    expect(isTransientSendError(new Error("chat not found"))).toBe(false);
  });
});
