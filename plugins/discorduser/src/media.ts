import { createWriteStream, mkdtempSync, rmSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const DEFAULT_MAX_MB = 25;

const ALLOWED_MEDIA_DOMAINS = [
  'cdn.discordapp.com',
  'media.discordapp.net',
  'images-ext-1.discordapp.net',
  'images-ext-2.discordapp.net',
  'attachments.discordapp.net',
];

const PRIVATE_IP_RANGES = [
  /^10\./,
  /^172\.(1[6-9]|2\d|3[01])\./,
  /^192\.168\./,
  /^127\./,
  /^::1$/,
  /^fc00:/,
  /^fe80:/,
];

function isAllowedMediaUrl(urlStr: string): boolean {
  try {
    const url = new URL(urlStr);
    const hostname = url.hostname.toLowerCase();

    // Block private IP ranges
    if (PRIVATE_IP_RANGES.some(range => range.test(hostname))) {
      return false;
    }

    // Only allow Discord CDN domains
    return ALLOWED_MEDIA_DOMAINS.some(domain =>
      hostname === domain || hostname.endsWith('.' + domain)
    );
  } catch {
    return false;
  }
}

export async function downloadToTemp(url: string, maxMb = DEFAULT_MAX_MB): Promise<string> {
  if (!isAllowedMediaUrl(url)) {
    throw new Error(`Media URL not allowed: ${url}`);
  }

  const maxBytes = maxMb * 1024 * 1024;

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to download ${url}: ${response.status} ${response.statusText}`);
  }

  const contentLength = response.headers.get("content-length");
  if (contentLength) {
    const size = Number(contentLength);
    if (size > maxBytes) {
      throw new Error(
        `File size ${(size / 1024 / 1024).toFixed(2)}MB exceeds limit of ${maxMb}MB`,
      );
    }
  }

  const body = response.body;
  if (!body) {
    throw new Error(`Failed to download ${url}: response body is null`);
  }

  const tempDir = mkdtempSync(join(tmpdir(), "discorduser-media-"));
  try {
    const ext = inferExtension(url);
    const tempPath = join(tempDir, `download${ext}`);

    let bytesWritten = 0;
    const fileStream = createWriteStream(tempPath);

    try {
      const reader = body.getReader();
      try {
        for (;;) {
          const { done, value } = await reader.read();
          if (done) break;
          bytesWritten += value.byteLength;
          if (bytesWritten > maxBytes) {
            reader.cancel();
            throw new Error(
              `Downloaded file size exceeds limit of ${maxMb}MB (aborted at ${(bytesWritten / 1024 / 1024).toFixed(2)}MB)`,
            );
          }
          fileStream.write(value);
        }
      } finally {
        reader.releaseLock();
      }
    } finally {
      await new Promise<void>((resolve, reject) => {
        fileStream.end((err: Error | null | undefined) => (err ? reject(err) : resolve()));
      });
    }

    return tempPath;
  } catch (err) {
    rmSync(tempDir, { recursive: true, force: true });
    throw err;
  }
}

export function inferMediaType(url: string): string {
  const ext = inferExtension(url).toLowerCase();
  const mimeMap: Record<string, string> = {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".gif": "image/gif",
    ".webp": "image/webp",
    ".mp4": "video/mp4",
    ".mov": "video/quicktime",
    ".avi": "video/x-msvideo",
    ".webm": "video/webm",
    ".mp3": "audio/mpeg",
    ".wav": "audio/wav",
    ".ogg": "audio/ogg",
    ".pdf": "application/pdf",
    ".txt": "text/plain",
    ".json": "application/json",
    ".xml": "application/xml",
  };
  return mimeMap[ext] ?? "application/octet-stream";
}

export async function cleanupTempFile(path: string): Promise<void> {
  try {
    unlinkSync(path);
    // Also remove the temp directory created by mkdtempSync
    const dir = dirname(path);
    if (dir.includes("discorduser-media-")) {
      rmSync(dir, { recursive: false });
    }
  } catch (err) {
    console.error(`[discorduser] failed to cleanup temp file ${path}: ${String(err)}`);
  }
}

function inferExtension(url: string): string {
  try {
    const parsed = new URL(url);
    const pathname = parsed.pathname;
    const lastDot = pathname.lastIndexOf(".");
    if (lastDot !== -1 && lastDot < pathname.length - 1) {
      return pathname.slice(lastDot);
    }
  } catch {
    // Invalid URL, try simple string parsing
    const lastDot = url.lastIndexOf(".");
    const lastSlash = url.lastIndexOf("/");
    if (lastDot !== -1 && lastDot > lastSlash) {
      return url.slice(lastDot);
    }
  }
  return "";
}
