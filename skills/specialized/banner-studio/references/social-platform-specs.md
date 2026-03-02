# Social Platform Image Specifications

Quick reference for banner and image dimensions across social platforms.

---

## Twitter / X

| Type | Dimensions | Aspect Ratio | Notes |
|------|-----------|--------------|-------|
| Card (OG) | 1200 x 628 | ~1.91:1 | Link preview cards |
| Post image | 1600 x 900 | 16:9 | In-feed image posts |
| Header/Banner | 1500 x 500 | 3:1 | Profile header |
| Profile photo | 400 x 400 | 1:1 | Circular crop |

**Safe zone**: Keep text 60px from edges for card images (UI overlays vary).

---

## Discord

| Type | Dimensions | Aspect Ratio | Notes |
|------|-----------|--------------|-------|
| Embed image | 1200 x 675 | ~16:9 | Bot embed thumbnails/images |
| Server banner | 960 x 540 | 16:9 | Server boost banner |
| Server icon | 512 x 512 | 1:1 | Circular crop |
| Role icon | 64 x 64 | 1:1 | Small badge |

**Note**: Embed images auto-resize; 1200x675 ensures sharp rendering.

---

## Telegram

| Type | Dimensions | Aspect Ratio | Notes |
|------|-----------|--------------|-------|
| Channel photo | 640 x 640 | 1:1 | Circular crop |
| Post image | 1280 x 720 | 16:9 | In-chat images |
| Sticker | 512 x 512 | 1:1 | Max dimension, can be non-square |

---

## LinkedIn

| Type | Dimensions | Aspect Ratio | Notes |
|------|-----------|--------------|-------|
| Post image | 1200 x 627 | ~1.91:1 | In-feed posts |
| Cover photo | 1584 x 396 | 4:1 | Profile/company cover |
| Profile photo | 400 x 400 | 1:1 | Circular crop |
| Article cover | 1200 x 644 | ~1.86:1 | Article header |

---

## General / Open Graph

| Type | Dimensions | Aspect Ratio | Notes |
|------|-----------|--------------|-------|
| OG image | 1200 x 630 | ~1.91:1 | Universal link preview |
| Square post | 1080 x 1080 | 1:1 | Multi-platform square |
| Story/Vertical | 1080 x 1920 | 9:16 | Mobile-first vertical |

**OG image** is the safest default — works across Twitter, Discord, LinkedIn, Slack, and most link previews.

---

## Recommended Defaults

For most use cases, start with these:

| Use Case | Recommended Size |
|----------|-----------------|
| Announcement / news | 1200 x 675 (Discord/OG) |
| Twitter post | 1600 x 900 |
| Link preview card | 1200 x 630 |
| Square metric card | 1080 x 1080 |
| Profile header | 1500 x 500 |
| Mobile story | 1080 x 1920 |

---

## File Format Notes

- **PNG**: Best for text-heavy banners, sharp edges, transparency
- **JPEG**: Smaller file size, good for photo-heavy backgrounds
- **Recommended**: PNG at 72 DPI for web/social — matches generate.py default output
