# Presentation Design Patterns

Design principles, color palettes, typography, and layout guidance for creating professional presentations. Reference this when planning slide aesthetics.

---

## Choosing a Color Palette

Choose colors that match the topic and brand. Never default to generic blue. Pick a palette before writing any code.

**Structure**: One dominant color (60-70% weight), 1-2 supporting tones, one sharp accent.

| Theme | Primary | Secondary | Accent | Good For |
|-------|---------|-----------|--------|----------|
| **Midnight Executive** | `1E2761` (navy) | `CADCFC` (ice blue) | `FFFFFF` (white) | Investor decks, corporate |
| **Forest & Moss** | `2C5F2D` (forest) | `97BC62` (moss) | `F5F5F5` (cream) | Sustainability, growth |
| **Coral Energy** | `F96167` (coral) | `F9E795` (gold) | `2F3C7E` (navy) | Marketing, launches |
| **Warm Terracotta** | `B85042` (terracotta) | `E7E8D1` (sand) | `A7BEAE` (sage) | Executive summaries |
| **Ocean Gradient** | `065A82` (deep blue) | `1C7293` (teal) | `02C39A` (mint) | Tech, performance |
| **Charcoal Minimal** | `36454F` (charcoal) | `F2F2F2` (off-white) | `212121` (black) | Minimalist, editorial |
| **Teal Trust** | `028090` (teal) | `00A896` (seafoam) | `02C39A` (mint) | Finance, data |
| **Berry & Cream** | `6D2E46` (berry) | `A26769` (dusty rose) | `ECE2D0` (cream) | Lifestyle, creative |
| **Dark Premium** | `212121` (black) | `333333` (charcoal) | `00D4AA` (emerald) | Premium, product launches |
| **Cherry Bold** | `990011` (cherry) | `FCF6F5` (off-white) | `2F3C7E` (navy) | Bold statements, sales |

If the user has brand colors, use those instead. Derive a full palette from brand colors: primary = brand color, secondary = lighter/darker variant, accent = complementary or contrasting.

### Palette as Python Dictionary

```python
PALETTE = {
    "bg_dark": RGBColor(0x1E, 0x27, 0x61),
    "bg_light": RGBColor(0xF5, 0xF5, 0xF7),
    "accent": RGBColor(0x02, 0xC3, 0x9A),
    "text_light": RGBColor(0xFF, 0xFF, 0xFF),
    "text_dark": RGBColor(0x1A, 0x1A, 0x2E),
    "text_muted": RGBColor(0x66, 0x66, 0x80),
}
```

---

## Dark/Light Sandwich Structure

Use dark backgrounds for title + closing slides, light backgrounds for content. This creates visual rhythm:

```
Slide 1: Dark  (Title)
Slide 2: Light (Content)
Slide 3: Light (Content)
Slide 4: Light (Content)
Slide 5: Dark  (Closing)
```

Or commit to dark throughout for a premium feel.

---

## Typography

Use font pairings available on both Windows and Google Slides:

| Header Font | Body Font | Vibe |
|-------------|-----------|------|
| **Calibri** | Calibri Light | Clean, modern |
| **Arial Black** | Arial | Bold, corporate |
| **Georgia** | Calibri | Classic, trustworthy |
| **Trebuchet MS** | Calibri | Friendly, tech |
| **Cambria** | Calibri | Traditional, academic |

### Size Guide

| Element | Size |
|---------|------|
| Slide title | 36-44pt bold |
| Section header | 20-24pt bold |
| Body text | 14-16pt |
| Captions/footnotes | 10-12pt muted |

---

## Layout Rules

- **0.5" minimum margins** from all slide edges
- **0.3-0.5" gaps** between content blocks
- **One key idea per slide** — if you need more space, add a slide
- **Vary layouts** — don't repeat the same layout on consecutive slides
- **Left-align body text** — only center titles and single-line callouts
- **Every slide needs a visual** — chart, icon shape, colored block, or image
- **Commit to a visual motif** — pick ONE distinctive element and repeat it (rounded frames, icons in circles, thick borders)

---

## Slide Layout Ideas

- **Two-column**: Text left, visual right (or reversed)
- **Big number callout**: 60-72pt stat with small label below
- **Icon + text rows**: Colored circle, bold header, description
- **Comparison columns**: Before/after, pros/cons side by side
- **Timeline/process**: Numbered steps with connecting elements
- **Metric cards**: 3 cards in a row with key stats
- **Half-bleed**: Full-width color band on top or bottom third
- **2x2 or 2x3 grid**: Image on one side, grid of content blocks on other
- **Half-bleed image**: Full left or right side with content overlay

---

## Things to Avoid

- Text-only slides with no visual elements
- Same layout repeated on every slide
- Light text on light backgrounds (contrast matters)
- Centered body paragraphs (center only titles)
- Cramming too much content onto one slide
- Default PowerPoint template aesthetics
- **NEVER accent lines under titles** — hallmark of AI-generated slides; use whitespace or background color instead
- Low-contrast icons (dark icons on dark backgrounds without a contrasting circle)
- Text boxes too narrow causing excessive wrapping
- Mixing spacing randomly — choose 0.3" or 0.5" gaps and use consistently
- Styling one slide and leaving the rest plain — commit fully or keep it simple throughout

---

## Helper Functions

Use consistent helpers across all slides to avoid repetition:

```python
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.enum.shapes import MSO_SHAPE

def add_text(slide, text, x, y, w, h, font_size=16, bold=False,
             color=None, font_name="Calibri", alignment=PP_ALIGN.LEFT):
    """Add a text box with common settings."""
    txBox = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = txBox.text_frame
    tf.word_wrap = True
    tf.margin_left = Inches(0)
    tf.margin_right = Inches(0)
    tf.margin_top = Inches(0)
    tf.margin_bottom = Inches(0)
    p = tf.paragraphs[0]
    p.text = text
    p.font.size = Pt(font_size)
    p.font.bold = bold
    p.font.name = font_name
    if color:
        p.font.color.rgb = color
    p.alignment = alignment
    return tf

def add_accent_bar(slide, x, y, w, color, h=0.06):
    """Add a thin colored accent line."""
    shape = slide.shapes.add_shape(
        MSO_SHAPE.RECTANGLE,
        Inches(x), Inches(y), Inches(w), Inches(h)
    )
    shape.fill.solid()
    shape.fill.fore_color.rgb = color
    shape.line.fill.background()

def add_card(slide, x, y, w, h, accent_color=None):
    """Add a white card with optional accent bar at top."""
    card = slide.shapes.add_shape(
        MSO_SHAPE.ROUNDED_RECTANGLE,
        Inches(x), Inches(y), Inches(w), Inches(h)
    )
    card.fill.solid()
    card.fill.fore_color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
    card.line.color.rgb = RGBColor(0xE8, 0xE8, 0xE8)
    card.line.width = Pt(0.5)
    if accent_color:
        add_accent_bar(slide, x, y, w, accent_color, 0.05)
    return card
```

Use `add_text()`, `add_card()`, and `add_accent_bar()` with palette colors. This keeps the code readable and ensures visual consistency.
