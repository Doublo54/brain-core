# Reading & Extracting Content from PPTX Files

Use this reference when you need to **read**, **analyze**, or **extract** content from existing `.pptx` files. This covers text extraction with markitdown, slide analysis, and content inspection workflows.

---

## Quick Reference

| Task | Command |
|------|---------|
| Extract all text | `python -m markitdown presentation.pptx` |
| Extract to file | `python -m markitdown presentation.pptx > content.md` |
| Check for placeholders | `python -m markitdown output.pptx \| grep -iE "xxxx\|lorem\|ipsum"` |
| Programmatic inspection | Use python-pptx `Presentation()` API (see below) |

---

## markitdown: Text Extraction

[markitdown](https://github.com/microsoft/markitdown) converts PPTX files to clean Markdown text, extracting all slide content including titles, body text, speaker notes, and table data.

### Installation

```bash
pip install "markitdown[pptx]" --break-system-packages
```

### Basic Usage

```bash
# Extract all text content as Markdown
python -m markitdown presentation.pptx

# Save to file for further processing
python -m markitdown presentation.pptx > extracted.md

# Pipe to other tools
python -m markitdown presentation.pptx | wc -w  # word count
```

### What markitdown Extracts

- Slide titles and body text
- Speaker notes
- Table content (as Markdown tables)
- Text from shapes and text boxes
- Bullet points and numbered lists
- Slide separators (by slide number)

### What markitdown Does NOT Extract

- Images (descriptions only if alt-text exists)
- Charts (data values, not visual representation)
- Animations or transitions
- Formatting (bold, italic, colors, fonts)
- Shape positions or layout information

### Python API

```python
from markitdown import MarkItDown

md = MarkItDown()
result = md.convert("presentation.pptx")
print(result.text_content)

# Process slide by slide
for slide_text in result.text_content.split("<!-- Slide"):
    if slide_text.strip():
        print(f"--- Slide ---\n{slide_text}")
```

---

## Use Cases

### 1. Summarize an Existing Presentation

```bash
# Extract text, then process
python -m markitdown presentation.pptx > /tmp/deck-content.md
```

Then read the extracted Markdown to summarize, answer questions about, or restructure the content.

### 2. Extract Content for Reuse

When asked to create a new presentation based on an existing one:

```bash
# Step 1: Extract content from source
python -m markitdown source-deck.pptx > /tmp/source-content.md

# Step 2: Review extracted content
# Step 3: Use content to build new deck with python-pptx
```

### 3. QA — Verify Generated Presentations

After creating a presentation with python-pptx, verify the content:

```bash
# Check that all expected text made it into the slides
python -m markitdown output.pptx

# Check for leftover placeholder text from templates
python -m markitdown output.pptx | grep -iE "xxxx|lorem|ipsum|placeholder|click to|this.*(page|slide).*layout"
```

### 4. Compare Before/After

```bash
# Extract both versions
python -m markitdown original.pptx > /tmp/original.md
python -m markitdown updated.pptx > /tmp/updated.md

# Diff the content
diff /tmp/original.md /tmp/updated.md
```

### 5. Content Analysis for Restructuring

```bash
# Count slides
python -m markitdown presentation.pptx | grep -c "^# "

# Find all slide titles
python -m markitdown presentation.pptx | grep "^# "

# Check total word count
python -m markitdown presentation.pptx | wc -w
```

---

## Programmatic Inspection with python-pptx

For deeper analysis beyond text extraction (layout, positioning, shapes, formatting):

### Inspect Slide Structure

```python
from pptx import Presentation

prs = Presentation("presentation.pptx")
print(f"Slides: {len(prs.slides)}")
print(f"Dimensions: {prs.slide_width} x {prs.slide_height}")

for i, slide in enumerate(prs.slides, 1):
    print(f"\n--- Slide {i} ---")
    for shape in slide.shapes:
        print(f"  Shape: {shape.shape_type}, Name: {shape.name}")
        print(f"    Position: ({shape.left}, {shape.top})")
        print(f"    Size: {shape.width} x {shape.height}")
        if shape.has_text_frame:
            for para in shape.text_frame.paragraphs:
                print(f"    Text: {para.text[:80]}")
```

### Inspect Templates & Layouts

```python
prs = Presentation("template.pptx")

for i, layout in enumerate(prs.slide_layouts):
    print(f"Layout {i}: {layout.name}")
    for ph in layout.placeholders:
        print(f"  Placeholder {ph.placeholder_format.idx}: {ph.name}")
        print(f"    Size: {ph.width} x {ph.height}")
        print(f"    Position: ({ph.left}, {ph.top})")
```

### Extract Speaker Notes

```python
prs = Presentation("presentation.pptx")

for i, slide in enumerate(prs.slides, 1):
    if slide.has_notes_slide:
        notes = slide.notes_slide.notes_text_frame.text
        if notes.strip():
            print(f"Slide {i} notes: {notes}")
```

### Extract Images

```python
import os
from pptx import Presentation

prs = Presentation("presentation.pptx")
os.makedirs("/tmp/extracted-images", exist_ok=True)

img_count = 0
for slide in prs.slides:
    for shape in slide.shapes:
        if shape.shape_type == 13:  # Picture
            img_count += 1
            image = shape.image
            ext = image.content_type.split("/")[-1]
            with open(f"/tmp/extracted-images/image-{img_count}.{ext}", "wb") as f:
                f.write(image.blob)

print(f"Extracted {img_count} images")
```

---

## Visual Inspection (Converting to Images)

For visual QA, convert slides to images:

```bash
# Convert PPTX to PDF, then PDF to images
python scripts/office/soffice.py --headless --convert-to pdf output.pptx
pdftoppm -jpeg -r 150 output.pdf slide
# Creates slide-01.jpg, slide-02.jpg, etc.

# Re-render specific slides after fixes
pdftoppm -jpeg -r 150 -f N -l N output.pdf slide-fixed
```

**Dependencies for visual inspection:**
- LibreOffice (`soffice`) — PPTX to PDF conversion
- Poppler (`pdftoppm`) — PDF to image conversion

---

## Combined Workflow: Read → Analyze → Create

When the user provides a PPTX and wants a new version:

```
1. Extract text:     python -m markitdown input.pptx > /tmp/content.md
2. Inspect layout:   python-pptx Presentation() API for structure
3. Plan new deck:    Based on extracted content + user requirements
4. Generate:         python-pptx to create new .pptx
5. Verify:           python -m markitdown output.pptx (content QA)
6. Visual QA:        Convert to images, inspect with subagent
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `markitdown` not found | `pip install "markitdown[pptx]" --break-system-packages` |
| Empty output from markitdown | File may contain only images/charts — use python-pptx inspection instead |
| Garbled text | Check if text is in shapes vs. placeholders; try python-pptx direct extraction |
| Can't open PPTX | Verify file isn't corrupted: `python3 -c "from pptx import Presentation; Presentation('file.pptx')"` |
| Missing speaker notes | markitdown extracts notes; if missing, check with python-pptx `slide.notes_slide` |
