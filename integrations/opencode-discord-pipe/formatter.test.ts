import { describe, expect, it, vi } from "vitest";

// Mock config.ts to avoid process.exit during import
vi.mock("./config.js", () => ({
  MAX_CODE_BLOCK: 1800,
  MAX_TOOL_OUTPUT: 1200,
}));

import { sanitizeOutput, formatSessionCreated, formatUserMessage } from "./formatter.js";

describe("opencode-discord-pipe sanitizeOutput", () => {
  it("redacts connection URIs", () => {
    const input = "mongodb://user:pass@localhost:27017/db";
    const result = sanitizeOutput(input);
    expect(result).toBe("mongodb://[REDACTED]");
  });

  it("redacts postgres connection strings", () => {
    const input = "postgres://admin:secret@db.example.com:5432/mydb";
    const result = sanitizeOutput(input);
    expect(result).toBe("postgres://[REDACTED]");
  });

  it("redacts Bearer tokens", () => {
    const input = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9";
    const result = sanitizeOutput(input);
    expect(result).toContain("[REDACTED]");
    expect(result).not.toContain("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9");
  });

  it("redacts long hex/base64 tokens", () => {
    const longToken = "a".repeat(50);
    const input = `Token: ${longToken}`;
    const result = sanitizeOutput(input);
    expect(result).toContain("[REDACTED]");
    expect(result).not.toContain(longToken);
  });

  it("neutralizes @everyone mentions", () => {
    const input = "Hey @everyone check this out!";
    const result = sanitizeOutput(input);
    expect(result).not.toContain("@everyone");
    expect(result).toContain("@\u200beveryone");
  });

  it("neutralizes @here mentions", () => {
    const input = "Alert @here now!";
    const result = sanitizeOutput(input);
    expect(result).not.toContain("@here");
    expect(result).toContain("@\u200bhere");
  });

  it("redacts environment variables with sensitive keys", () => {
    const input = "API_KEY=sk-1234567890abcdef";
    const result = sanitizeOutput(input);
    expect(result).toBe("API_KEY=[REDACTED]");
  });

  it("redacts JWT_SECRET assignments", () => {
    const input = "export JWT_SECRET=my-super-secret-key";
    const result = sanitizeOutput(input);
    expect(result).toContain("[REDACTED]");
    expect(result).not.toContain("my-super-secret-key");
  });

  it("redacts DATABASE_URL assignments", () => {
    const input = "DATABASE_URL: postgres://localhost/db";
    const result = sanitizeOutput(input);
    expect(result).toContain("[REDACTED]");
  });

  it("preserves safe content", () => {
    const input = "Hello world! This is a normal message.";
    const result = sanitizeOutput(input);
    expect(result).toBe(input);
  });

  it("handles multi-line content with mixed safe and sensitive data", () => {
    const input = `
LOG_LEVEL=info
API_KEY=secret123
MESSAGE=Hello world
PASSWORD=hunter2
    `.trim();
    const result = sanitizeOutput(input);
    expect(result).toContain("LOG_LEVEL=info");
    expect(result).toContain("MESSAGE=Hello world");
    expect(result).toContain("API_KEY=[REDACTED]");
    expect(result).toContain("PASSWORD=[REDACTED]");
    expect(result).not.toContain("secret123");
    expect(result).not.toContain("hunter2");
  });
});

describe("opencode-discord-pipe formatSessionCreated", () => {
  it("formats session with all fields", () => {
    const info = {
      id: "ses_123",
      slug: "my-session",
      title: "Test Session",
      directory: "/home/user/project",
    };
    const result = formatSessionCreated(info);
    expect(result).toContain("🆕 **New Session**");
    expect(result).toContain("`my-session`");
    expect(result).toContain("Test Session");
    expect(result).toContain("/home/user/project");
  });

  it("handles missing optional fields", () => {
    const info = {
      id: "ses_456",
    };
    const result = formatSessionCreated(info);
    expect(result).toContain("🆕 **New Session**");
    expect(result).toContain("`ses_456`");
    expect(result).toContain("Untitled");
    expect(result).toContain("?");
  });
});

describe("opencode-discord-pipe formatUserMessage", () => {
  it("formats short user message", () => {
    const sessions = new Map();
    sessions.set("ses_1", { slug: "test-session" });
    
    const part = {
      sessionID: "ses_1",
      text: "Hello, how are you?",
    };
    
    const result = formatUserMessage(part, sessions);
    expect(result).toContain("📋 **Prompt**");
    expect(result).toContain("`test-session`");
    expect(result).toContain("Hello, how are you?");
  });

  it("truncates long user messages", () => {
    const sessions = new Map();
    sessions.set("ses_2", { slug: "long-session" });
    
    const longText = "a".repeat(2000);
    const part = {
      sessionID: "ses_2",
      text: longText,
    };
    
    const result = formatUserMessage(part, sessions);
    expect(result).toContain("truncated");
    expect(result).toContain("2000 chars total");
  });

  it("returns null for empty text", () => {
    const sessions = new Map();
    const part = {
      sessionID: "ses_3",
      text: "",
    };
    
    const result = formatUserMessage(part, sessions);
    expect(result).toBeNull();
  });

  it("sanitizes user message content", () => {
    const sessions = new Map();
    sessions.set("ses_4", { slug: "sanitize-test" });
    
    const part = {
      sessionID: "ses_4",
      text: "API_KEY=secret123",
    };
    
    const result = formatUserMessage(part, sessions);
    expect(result).toContain("[REDACTED]");
    expect(result).not.toContain("secret123");
  });
});
