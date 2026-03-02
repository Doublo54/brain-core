# Banner Template Guide

How to create, customize, and test HTML banner templates for Banner Studio.

---

## Template Basics

A banner template is a standalone HTML file that:

1. Has fixed dimensions (set via CSS on `body` or a container element)
2. Uses `{{variable}}` placeholders for dynamic content
3. Uses inline CSS only (no CDN links, no external stylesheets)
4. Renders correctly without internet access

---

## Placeholder Syntax

Use double curly braces for dynamic values:

```html
<h1>{{title}}</h1>
<p>{{subtitle}}</p>
<div style="background: {{accent_color}};">Highlight</div>
```

Placeholders are replaced via simple string substitution before rendering.
Any `{{key}}` in the HTML is replaced with the corresponding value from `--data` JSON.

### Common Variables

| Variable | Example Value | Description |
|----------|--------------|-------------|
| `{{title}}` | "Q4 Results" | Main heading |
| `{{subtitle}}` | "Record growth" | Secondary text |
| `{{accent_color}}` | "#6C5CE7" | Theme color (hex) |
| `{{metric}}` | "1.5M" | Featured number |
| `{{metric_label}}` | "Total Users" | Label for metric |
| `{{date}}` | "Jan 2026" | Date string |
| `{{brand_dir}}` | "/path/to/brand" | Auto-injected when --brand-dir is set |

You can define any custom variables — just ensure they're passed via `--data`.

---

## Template Structure

### Minimal Template

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    width: 1200px;
    height: 675px;
    overflow: hidden;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    background: #0F0F1A;
    color: #FFFFFF;
    display: flex;
    align-items: center;
    justify-content: center;
  }
  .banner {
    width: 100%;
    height: 100%;
    padding: 60px;
    display: flex;
    flex-direction: column;
    justify-content: center;
  }
  .title { font-size: 56px; font-weight: 800; }
  .subtitle { font-size: 24px; color: #A0A0B0; margin-top: 16px; }
</style>
</head>
<body>
  <div class="banner">
    <h1 class="title">{{title}}</h1>
    <p class="subtitle">{{subtitle}}</p>
  </div>
</body>
</html>
```

### Key Rules

1. **Set body dimensions explicitly** — `width` and `height` on `body` or root container
2. **Use `overflow: hidden`** — Prevents scroll bars in the rendered screenshot
3. **Inline all CSS** — No `<link>` tags, no `@import`, no CDN references
4. **System font stack** — Use `-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif`

---

## Supported CSS Features

Playwright's Chromium renderer supports all modern CSS:

| Feature | Support | Notes |
|---------|---------|-------|
| Flexbox | Full | Recommended for layout |
| Grid | Full | Good for metric cards |
| Gradients | Full | `linear-gradient`, `radial-gradient`, `conic-gradient` |
| Transforms | Full | `rotate`, `scale`, `translate` |
| Filters | Full | `blur()`, `brightness()`, `drop-shadow()` |
| Clipping | Full | `clip-path` with all shapes |
| Custom properties | Full | `var(--color)` |
| `backdrop-filter` | Full | `blur()`, `saturate()` |
| Animations | Partial | First frame only (screenshot is static) |
| Web fonts (`@font-face`) | Full | Must be inline (base64) or local file |

### Fonts

For offline compatibility, either:

1. Use the system font stack (recommended)
2. Embed fonts as base64 in `@font-face`:

```css
@font-face {
  font-family: 'CustomFont';
  src: url(data:font/woff2;base64,d09GMgABAAAAAAL...) format('woff2');
}
```

---

## Offline Compatibility

Templates MUST work without internet. Avoid:

- `<script src="https://cdn...">` — No CDN scripts
- `<link href="https://fonts...">` — No Google Fonts CDN
- `<img src="https://...">` — Use local paths or base64 data URIs

Instead:

- Inline all CSS in `<style>` tags
- Use base64 data URIs for images: `<img src="data:image/png;base64,...">`
- Use system fonts or base64-embedded `@font-face`

---

## Using Brand Assets

When `--brand-dir` is set, templates can reference brand files:

```html
<img src="{{brand_dir}}/logo-light.svg" alt="Logo" style="height: 40px;">
```

Expected brand directory structure:

```
brand/
├── colors.json       # Color palette
├── logo-light.svg    # Logo for dark backgrounds
└── logo-dark.svg     # Logo for light backgrounds
```

The `colors.json` values are available as `{{brand_colors}}` (JSON string).

---

## Testing Templates Locally

### Quick Test

```bash
python3 scripts/generate.py \
  --template your-template.html \
  --data '{"title": "Test", "subtitle": "Preview"}' \
  --output /tmp/test.png
```

### Browser Preview

Open the HTML file directly in a browser for rapid iteration:

```bash
# Replace placeholders manually for preview
sed 's/{{title}}/Test Title/g; s/{{subtitle}}/Test Subtitle/g; s/{{accent_color}}/#6C5CE7/g' \
  assets/templates/your-template.html > /tmp/preview.html
open /tmp/preview.html  # macOS
```

### Checklist

- [ ] Correct dimensions (check body width/height CSS)
- [ ] No placeholder text visible (`{{...}}` all replaced)
- [ ] Text is legible at target size
- [ ] Colors render correctly
- [ ] No external resource dependencies (works offline)
- [ ] No scroll bars (overflow: hidden)

---

## Template Examples by Use Case

| Use Case | Dimensions | Key Variables |
|----------|-----------|---------------|
| Announcement | 1200x675 | title, subtitle, accent_color |
| Metric card | 1080x1080 | metric, metric_label, title |
| Twitter header | 1500x500 | title, accent_color |
| Launch post | 1600x900 | title, subtitle, date, accent_color |
| Story/vertical | 1080x1920 | title, subtitle, metric |
