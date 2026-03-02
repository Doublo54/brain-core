import { describe, expect, it } from "vitest";
import { chunkDiscordText, isTransientSendError } from "./send.js";

describe("discorduser text chunking", () => {
  it("keeps short text as one chunk", () => {
    const chunks = chunkDiscordText("hello");
    expect(chunks).toEqual(["hello"]);
  });

  it("splits long text within discord limit", () => {
    const input = "a".repeat(5000);
    const chunks = chunkDiscordText(input);
    expect(chunks.length).toBeGreaterThan(1);
    expect(chunks.every((c) => c.length <= 2000)).toBe(true);
    expect(chunks.join("").length).toBe(5000);
  });

  it("prefers splitting at paragraph boundaries", () => {
    const para1 = "a".repeat(1500);
    const para2 = "b".repeat(1500);
    const input = `${para1}\n\n${para2}`;
    const chunks = chunkDiscordText(input);
    expect(chunks.length).toBe(2);
    expect(chunks[0]).toBe(para1);
    expect(chunks[1]).toBe(para2);
  });

  it("returns single empty-string chunk for empty input", () => {
    const chunks = chunkDiscordText("");
    expect(chunks).toEqual([""]);
  });
});

describe("discorduser transient send errors", () => {
  it("detects transient network errors", () => {
    expect(isTransientSendError(new Error("network timeout"))).toBe(true);
    expect(isTransientSendError(new Error("ECONNRESET"))).toBe(true);
    expect(isTransientSendError(new Error("fetch failed"))).toBe(true);
  });

  it("excludes rate limit errors from transient detection", () => {
    expect(isTransientSendError(new Error("429 Too Many Requests"))).toBe(false);
    expect(isTransientSendError(new Error("rate limit exceeded"))).toBe(false);
  });

  it("ignores non-transient errors", () => {
    expect(isTransientSendError(new Error("chat not found"))).toBe(false);
    expect(isTransientSendError(new Error("forbidden"))).toBe(false);
  });
});
