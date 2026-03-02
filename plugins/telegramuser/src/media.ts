import type { UserAdapter } from "./user-adapter.js";

const MEDIA_EXTENSIONS: Record<string, "photo" | "document"> = {
  ".jpg": "photo",
  ".jpeg": "photo",
  ".png": "photo",
  ".gif": "photo",
  ".webp": "photo",
  ".bmp": "photo",
  ".svg": "document",
  ".pdf": "document",
  ".zip": "document",
  ".mp4": "document",
  ".mp3": "document",
  ".ogg": "document",
  ".wav": "document",
  ".doc": "document",
  ".docx": "document",
  ".xls": "document",
  ".xlsx": "document",
};

function inferMediaType(url: string): "photo" | "document" {
  const pathname = url.split("?")[0].toLowerCase();
  for (const [ext, type] of Object.entries(MEDIA_EXTENSIONS)) {
    if (pathname.endsWith(ext)) return type;
  }
  return "document";
}

export async function sendMediaMessage(params: {
  adapter: UserAdapter;
  target: string;
  mediaUrl: string;
  caption?: string;
}): Promise<{ messageId: string }> {
  const type = inferMediaType(params.mediaUrl);
  return params.adapter.sendFile(params.target, {
    file: params.mediaUrl,
    caption: params.caption,
    forceDocument: type === "document",
  });
}
