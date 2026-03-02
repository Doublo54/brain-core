---
name: presentations
description: "Use this skill any time a .pptx file is involved — as input, output, or both. Covers creating slide decks (pitch, investor, team update), reading/extracting text from existing .pptx files, editing presentations, and uploading to Google Drive. Triggers: 'make a presentation', 'create slides', 'build a deck', 'pitch deck', 'read this pptx', 'summarize this deck', 'extract slides', or any request mentioning slides, presentations, or .pptx files."
metadata:
  openclaw:
    emoji: "📊"
    requires:
      bins: ["python3"]
    install:
      - kind: pip
        packages: ["python-pptx", "Pillow", "markitdown[pptx]"]
---

# Presentations Skill

Create and read professional presentations using **python-pptx** (creation) and **markitdown** (extraction).

## Quick Reference

| Task | Guide |
|------|-------|
| Read/analyze a .pptx | `python -m markitdown presentation.pptx` — see [references/reading-extraction.md](references/reading-extraction.md) |
| Create from scratch | See [references/python-pptx-guide.md](references/python-pptx-guide.md) |
| Design & aesthetics | See [references/design-patterns.md](references/design-patterns.md) |
| Use a branded template | Load template, inspect layouts with python-pptx |
| Upload to Google Drive | Use MCP `create_drive_file` tool |

---

## Reading Workflow

When the user provides a `.pptx` file or asks to analyze/summarize a presentation:

```
1. Extract text       → python -m markitdown file.pptx
2. Inspect structure  → python-pptx Presentation() API for shapes, layouts, images
3. Analyze content    → Summarize, answer questions, or plan restructuring
```

Full details: [references/reading-extraction.md](references/reading-extraction.md)

---

## Creation Workflow

```
1. Plan the deck     → Structure slides (title, agenda, content, data, closing)
2. Pick a palette    → See design-patterns.md — never default to generic blue
3. Generate .pptx    → python-pptx with blank layouts (index 6) for full control
4. QA the output     → markitdown to verify text + visual inspection
5. (Optional) Upload → Google Drive MCP create_drive_file
```

### Minimal Creation Example

```python
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN

prs = Presentation()
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)

slide = prs.slides.add_slide(prs.slide_layouts[6])
slide.background.fill.solid()
slide.background.fill.fore_color.rgb = RGBColor(0x1E, 0x27, 0x61)

txBox = slide.shapes.add_textbox(Inches(1), Inches(2.5), Inches(11), Inches(2))
tf = txBox.text_frame
tf.word_wrap = True
p = tf.paragraphs[0]
p.text = "Quarterly Performance Review"
p.font.size = Pt(44)
p.font.bold = True
p.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
p.alignment = PP_ALIGN.LEFT

prs.save("/tmp/output.pptx")
```

### Template-Based Approach

```python
prs = Presentation("/path/to/template.pptx")

for i, layout in enumerate(prs.slide_layouts):
    print(f"Layout {i}: {layout.name}")
    for ph in layout.placeholders:
        print(f"  Placeholder {ph.placeholder_format.idx}: {ph.name}")

slide = prs.slides.add_slide(prs.slide_layouts[0])
slide.placeholders[0].text = "Your Title Here"
prs.save("/tmp/output.pptx")
```

---

## Planning a Deck

Before writing any code, plan the slide structure:

- **Title slide**: Name, subtitle, date
- **Agenda/Overview**: What the deck covers
- **Content slides**: 1 key idea per slide, vary layouts
- **Data slides**: Charts, metrics, comparisons
- **Closing slide**: Summary, next steps, contact

Aim for **8-15 slides** for a standard presentation.

---

## Upload to Google Drive (Optional)

If a Google Workspace MCP server is available:

```
Tool: create_drive_file
Arguments:
  name: "Presentation Title.pptx"
  content: <base64 encoded .pptx>
  mime_type: "application/vnd.openxmlformats-officedocument.presentationml.presentation"
  folder_id: <optional>
  convert: true  # to auto-convert to native Google Slides
```

If no MCP is available, return the .pptx file directly.

---

## QA Checklist

After generating any presentation:

1. **Verify valid file**: `python3 -c "from pptx import Presentation; Presentation('/tmp/output.pptx')"`
2. **Content check**: `python -m markitdown /tmp/output.pptx` — verify all text present
3. **Placeholder scan**: `python -m markitdown /tmp/output.pptx | grep -iE "xxxx|lorem|ipsum|placeholder"`
4. **Slide count**: Matches planned structure
5. **No empty slides**: Every slide has content
6. **Color/font consistency**: All slides use chosen palette and font pairing

For visual QA, convert to images and inspect (see reading-extraction reference).

---

## Dependencies

```bash
pip install python-pptx Pillow "markitdown[pptx]" --break-system-packages
```

Verify:
```bash
python3 -c "from pptx import Presentation; print('python-pptx ready')"
python3 -c "from markitdown import MarkItDown; print('markitdown ready')"
```

Setup script: [scripts/setup-pptx.sh](scripts/setup-pptx.sh)
