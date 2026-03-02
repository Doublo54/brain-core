---
name: banner-studio
emoji: "\U0001F3A8"
description: "Create professional social media banners, promotional graphics, and visual assets from HTML templates. Renders HTML+CSS to PNG/JPEG at exact dimensions. Use when asked to create banners, social cards, promotional images, milestone announcements, or any visual marketing asset. Triggers: 'create a banner', 'make a social card', 'promotional graphic', 'marketing image', 'announcement banner'."
version: 2.0.0
metadata:
  openclaw:
    emoji: "\U0001F3A8"
    requires:
      bins: ["python3"]
    install:
      - kind: pip
        packages: ["playwright"]
      - kind: shell
        command: "playwright install chromium"
---

# Banner Studio

Generate professional banners and social media assets from HTML/CSS templates using Playwright.

## Quick Reference

| Task | Guide |
|------|-------|
| Create a banner | See workflow below |
| Template syntax | [references/template-guide.md](references/template-guide.md) |
| Platform dimensions | [references/social-platform-specs.md](references/social-platform-specs.md) |
| Setup dependencies | [scripts/setup-banner.sh](scripts/setup-banner.sh) |

---

## Workflow

```
1. Design     → Choose dimensions for target platform (see social-platform-specs.md)
2. Template   → Select or create HTML template with {{variable}} placeholders
3. Render     → Run generate.py to render HTML → PNG via Playwright
4. QA         → Verify output dimensions, text legibility, no placeholder leaks
```

---

## Quick Start

Render the built-in minimal template:

```bash
python3 {baseDir}/scripts/generate.py \
  --template minimal-banner.html \
  --data '{"title": "Launch Day", "subtitle": "Something big is coming", "accent_color": "#6C5CE7"}' \
  --output ./banner.png
```

Override dimensions for a specific platform:

```bash
python3 {baseDir}/scripts/generate.py \
  --template minimal-banner.html \
  --data '{"title": "Weekly Update", "subtitle": "Metrics & highlights"}' \
  --width 1600 --height 900 \
  --output ./twitter-post.png
```

Use org-specific brand assets:

```bash
python3 {baseDir}/scripts/generate.py \
  --template announcement.html \
  --template-dir /path/to/org/templates \
  --brand-dir /path/to/org/brand \
  --data '{"title": "New Feature", "subtitle": "Now live"}' \
  --output ./announcement.png
```

---

## generate.py Arguments

| Argument | Required | Default | Description |
|----------|----------|---------|-------------|
| `--template` | Yes | — | Template HTML filename |
| `--data` | No | `{}` | JSON string with template variables |
| `--output` | No | auto-named | Output PNG path |
| `--width` | No | 1200 | Output width in pixels |
| `--height` | No | 675 | Output height in pixels |
| `--template-dir` | No | `./assets/templates/` | Path to HTML templates |
| `--brand-dir` | No | None | Path to org-specific brand assets |

---

## Template Variables

All templates use `{{variable}}` syntax. The minimal template supports:

- `{{title}}` — Main heading text
- `{{subtitle}}` — Secondary text
- `{{accent_color}}` — Accent color (hex, e.g. `#6C5CE7`)

Custom templates can define any variables. See [references/template-guide.md](references/template-guide.md).

---

## Creating Custom Templates

1. Copy `assets/templates/minimal-banner.html` as a starting point
2. Edit HTML/CSS — all styles must be inline (no CDN links)
3. Add `{{variable}}` placeholders for dynamic content
4. Test: `python3 generate.py --template your-template.html --data '{"var": "value"}'`

Full guide: [references/template-guide.md](references/template-guide.md)

---

## Brand Directory Structure

When using `--brand-dir`, the directory should contain:

```
brand/
├── colors.json       # {"primary": "#hex", "secondary": "#hex", ...}
├── logo-light.svg    # Logo for dark backgrounds
└── logo-dark.svg     # Logo for light backgrounds
```

Templates can reference brand assets via `{{brand_dir}}` path variable (auto-injected when `--brand-dir` is set).

---

## Brand Content Storage (IMPORTANT)

This skill separates **skill logic** from **brand data**. Follow these rules strictly:

### What goes WHERE

| Content | Location | Why |
|---------|----------|-----|
| Skill logic (SKILL.md, scripts, references) | This skill directory (`{baseDir}/`) | Reusable across all orgs |
| Generic templates (no brand colors/logos baked in) | `{baseDir}/assets/templates/` | Reusable across all orgs |
| Brand-specific content (logos, colors, branded templates) | `{baseDir}/brand/` directory | Org-specific, version-controlled separately |

### Multi-brand layout

Your `brand/` directory (workspace symlink to org brand-assets) supports multiple brands as direct children:

```
brand/
├── colors.json                  # Org-level default color palette
├── templates/                   # Org-level branded templates
│   ├── launch-announcement.html
│   └── yield-card.html
└── {brand-name}/                # Per-brand content (direct child, no wrapper)
    ├── brand.json               # Brand color system, typography, design principles
    ├── README.md                # Brand guidelines
    ├── assets/                  # Brand visual assets (logos, SVGs, textures)
    │   ├── logo-light.svg
    │   └── ...
    └── templates/               # Brand-specific templates
        └── epoch-recap.html
```

### Rules

1. **NEVER** write brand-specific content (logos, brand colors, branded templates) into the skill's `assets/` directory
2. **ALWAYS** write brand content to `brand/{brand-name}/`
3. When creating a new brand, create the full directory structure under `brand/{brand-name}/`
4. Generic templates (with `{{variable}}` placeholders, no hardcoded brand values) belong in `assets/templates/`
5. Templates with hardcoded brand colors, logos, or styling belong in `brand/{brand-name}/templates/`
6. Reference brand assets in templates via `{{brand_dir}}/assets/filename.ext` (auto-injected by generate.py when `--brand-dir` is set)
7. All templates must use inline CSS — no CDN links (see QA checklist)

---

## Common Dimensions

| Platform | Type | Size |
|----------|------|------|
| Twitter/X | Card | 1200x628 |
| Twitter/X | Post | 1600x900 |
| Discord | Embed | 1200x675 |
| LinkedIn | Post | 1200x627 |
| General | OG Image | 1200x630 |

Full reference: [references/social-platform-specs.md](references/social-platform-specs.md)

---

## QA Checklist

After generating any banner:

1. **Dimensions correct**: Match target platform spec
2. **Text legible**: No overflow, truncation, or tiny text
3. **No placeholder leaks**: No `{{variable}}` visible in output
4. **Colors render**: Accent colors applied, contrast sufficient
5. **Offline OK**: Template works without internet (inline CSS, no CDN)

---

## Dependencies

```bash
pip install playwright --break-system-packages
playwright install chromium
```

Setup script: [scripts/setup-banner.sh](scripts/setup-banner.sh)
