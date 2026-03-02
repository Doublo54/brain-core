# python-pptx API Reference

Complete reference for creating presentations with python-pptx. This is the Python equivalent of the pptxgenjs guide — use this instead of the JS library.

## Setup & Installation

```bash
pip install python-pptx Pillow --break-system-packages
```

```python
from pptx import Presentation
from pptx.util import Inches, Pt, Emu, Cm
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR, MSO_AUTO_SIZE
from pptx.enum.shapes import MSO_SHAPE
from pptx.enum.chart import XL_CHART_TYPE
```

---

## Slide Dimensions

```python
prs = Presentation()

# 16:9 Widescreen (default for modern presentations)
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)

# Standard 16:9
prs.slide_width = Inches(10)
prs.slide_height = Inches(5.625)

# 4:3 Classic
prs.slide_width = Inches(10)
prs.slide_height = Inches(7.5)
```

**Use 13.333 x 7.5 for Google Slides compatibility** — this matches Google Slides' default widescreen dimensions.

---

## Slide Layouts

When creating from a blank Presentation(), these layouts are available:

| Index | Layout Name | Use For |
|-------|-------------|---------|
| 0 | Title Slide | Opening/title slides |
| 1 | Title and Content | Standard content |
| 2 | Section Header | Section dividers |
| 3 | Two Content | Two-column |
| 4 | Comparison | Side by side |
| 5 | Title Only | Custom layouts |
| 6 | **Blank** | **Full control (recommended)** |
| 7 | Content with Caption | Caption layouts |
| 8 | Picture with Caption | Image layouts |

**Always use layout index 6 (Blank)** for full design control. Pre-built layouts have placeholders that constrain positioning.

```python
blank_layout = prs.slide_layouts[6]
slide = prs.slides.add_slide(blank_layout)
```

---

## Text Boxes

### Basic Text

```python
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN

txBox = slide.shapes.add_textbox(
    Inches(1),    # left (x)
    Inches(2),    # top (y)
    Inches(10),   # width
    Inches(1.5)   # height
)
tf = txBox.text_frame
tf.word_wrap = True

p = tf.paragraphs[0]
p.text = "Hello World"
p.font.size = Pt(36)
p.font.bold = True
p.font.name = "Calibri"
p.font.color.rgb = RGBColor(0x1E, 0x27, 0x61)
p.alignment = PP_ALIGN.LEFT
```

### Multiple Paragraphs

```python
tf = txBox.text_frame
tf.word_wrap = True

# First paragraph (already exists)
p = tf.paragraphs[0]
p.text = "First paragraph"
p.font.size = Pt(16)
p.font.name = "Calibri"

# Additional paragraphs
p2 = tf.add_paragraph()
p2.text = "Second paragraph"
p2.font.size = Pt(16)
p2.font.name = "Calibri"
p2.space_before = Pt(8)
```

### Rich Text (Mixed Formatting)

```python
p = tf.paragraphs[0]

run1 = p.add_run()
run1.text = "Bold text "
run1.font.bold = True
run1.font.size = Pt(16)

run2 = p.add_run()
run2.text = "and normal text"
run2.font.bold = False
run2.font.size = Pt(16)
```

### Text Box Properties

```python
tf = txBox.text_frame

# Internal margins (padding inside the text box)
tf.margin_left = Inches(0.1)
tf.margin_right = Inches(0.1)
tf.margin_top = Inches(0.05)
tf.margin_bottom = Inches(0.05)

# Vertical alignment
tf.vertical_anchor = MSO_ANCHOR.MIDDLE  # TOP, MIDDLE, BOTTOM

# Auto-size behavior
tf.auto_size = MSO_AUTO_SIZE.NONE          # Fixed size (default)
tf.auto_size = MSO_AUTO_SIZE.TEXT_TO_FIT_SHAPE  # Shrink text to fit
tf.auto_size = MSO_AUTO_SIZE.SHAPE_TO_FIT_TEXT  # Grow box to fit text

# Word wrap
tf.word_wrap = True
```

### Paragraph Spacing

```python
p.space_before = Pt(6)   # Space before paragraph
p.space_after = Pt(6)    # Space after paragraph
p.line_spacing = Pt(20)  # Line spacing (fixed)
# Or use proportional: 1.0 = single, 1.5 = 1.5x, 2.0 = double
p.line_spacing = 1.15
```

### Bullets and Lists

```python
from pptx.oxml.ns import qn

# Simple bullet list
for item_text in ["First item", "Second item", "Third item"]:
    p = tf.add_paragraph()
    p.text = item_text
    p.font.size = Pt(14)
    p.level = 0  # 0 = top level, 1 = sub-item, etc.

    # Enable bullet
    pPr = p._pPr
    if pPr is None:
        pPr = p._p.get_or_add_pPr()
    buNone = pPr.find(qn('a:buNone'))
    if buNone is not None:
        pPr.remove(buNone)
    # Add bullet character
    buChar = pPr.makeelement(qn('a:buChar'), {'char': '•'})
    pPr.append(buChar)
```

**Simpler bullet approach** — use a dash or unicode bullet in the text itself:

```python
# Quick and dirty bullets (works well visually)
items = ["Revenue grew 127% QoQ", "18,420 active users", "3 new protocol integrations"]
for item in items:
    p = tf.add_paragraph()
    p.text = f"  •  {item}"
    p.font.size = Pt(16)
    p.space_before = Pt(8)
```

---

## Shapes

### Basic Shapes

```python
from pptx.enum.shapes import MSO_SHAPE

# Rectangle
shape = slide.shapes.add_shape(
    MSO_SHAPE.RECTANGLE,
    Inches(1),    # left
    Inches(1),    # top
    Inches(4),    # width
    Inches(2)     # height
)
shape.fill.solid()
shape.fill.fore_color.rgb = RGBColor(0x02, 0xC3, 0x9A)
shape.line.fill.background()  # No border

# Rounded rectangle
shape = slide.shapes.add_shape(
    MSO_SHAPE.ROUNDED_RECTANGLE,
    Inches(1), Inches(1), Inches(4), Inches(2)
)
shape.fill.solid()
shape.fill.fore_color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
shape.line.color.rgb = RGBColor(0xE0, 0xE0, 0xE0)
shape.line.width = Pt(1)

# Oval / Circle
shape = slide.shapes.add_shape(
    MSO_SHAPE.OVAL,
    Inches(5), Inches(1), Inches(2), Inches(2)  # Equal w/h = circle
)

# Line (use a very thin rectangle or connector)
line = slide.shapes.add_shape(
    MSO_SHAPE.RECTANGLE,
    Inches(1), Inches(3), Inches(8), Inches(0.02)
)
line.fill.solid()
line.fill.fore_color.rgb = RGBColor(0xE0, 0xE0, 0xE0)
line.line.fill.background()
```

### Available Shapes

Common shapes: `RECTANGLE`, `ROUNDED_RECTANGLE`, `OVAL`, `TRIANGLE`, `DIAMOND`, `PENTAGON`, `HEXAGON`, `RIGHT_ARROW`, `LEFT_ARROW`, `CHEVRON`, `STAR_5_POINT`, `HEART`, `CLOUD`

### Shape with Text

```python
shape = slide.shapes.add_shape(
    MSO_SHAPE.ROUNDED_RECTANGLE,
    Inches(1), Inches(1), Inches(4), Inches(2)
)
shape.fill.solid()
shape.fill.fore_color.rgb = RGBColor(0x02, 0xC3, 0x9A)
shape.line.fill.background()

# Add text to shape
tf = shape.text_frame
tf.word_wrap = True
tf.vertical_anchor = MSO_ANCHOR.MIDDLE
p = tf.paragraphs[0]
p.text = "Click Here"
p.font.size = Pt(18)
p.font.bold = True
p.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
p.alignment = PP_ALIGN.CENTER
```

### Shadow (via XML)

python-pptx doesn't have a clean shadow API, but you can simulate depth with overlapping shapes:

```python
# Shadow card pattern: dark shape behind, white shape on top
shadow = slide.shapes.add_shape(
    MSO_SHAPE.ROUNDED_RECTANGLE,
    Inches(1.05), Inches(1.05), Inches(4), Inches(2)
)
shadow.fill.solid()
shadow.fill.fore_color.rgb = RGBColor(0xD0, 0xD0, 0xD0)
shadow.line.fill.background()

card = slide.shapes.add_shape(
    MSO_SHAPE.ROUNDED_RECTANGLE,
    Inches(1), Inches(1), Inches(4), Inches(2)
)
card.fill.solid()
card.fill.fore_color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
card.line.fill.background()
```

For real XML-based shadows:

```python
from pptx.oxml.ns import qn
from lxml import etree

shape = slide.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE,
    Inches(1), Inches(1), Inches(4), Inches(2))
shape.fill.solid()
shape.fill.fore_color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
shape.line.fill.background()

# Add outer shadow via XML
spPr = shape._element.spPr
effectLst = spPr.makeelement(qn('a:effectLst'), {})
outerShdw = effectLst.makeelement(qn('a:outerShdw'), {
    'blurRad': '76200',     # 6pt blur in EMU
    'dist': '25400',        # 2pt offset
    'dir': '5400000',       # 90 degrees (down) in 60,000ths of degree
    'algn': 'tl',
    'rotWithShape': '0'
})
srgbClr = outerShdw.makeelement(qn('a:srgbClr'), {'val': '000000'})
alpha = srgbClr.makeelement(qn('a:alpha'), {'val': '20000'})  # 20% opacity
srgbClr.append(alpha)
outerShdw.append(srgbClr)
effectLst.append(outerShdw)
spPr.append(effectLst)
```

---

## Slide Backgrounds

```python
# Solid color background
slide.background.fill.solid()
slide.background.fill.fore_color.rgb = RGBColor(0x1A, 0x1A, 0x2E)

# Gradient background (via XML)
from pptx.oxml.ns import qn

bg = slide.background
bgPr = bg._element.get_or_add_bgPr()
# Clear existing fill
for child in list(bgPr):
    bgPr.remove(child)

gradFill = bgPr.makeelement(qn('a:gradFill'), {})
gsLst = gradFill.makeelement(qn('a:gsLst'), {})

# Stop 1: Dark
gs1 = gsLst.makeelement(qn('a:gs'), {'pos': '0'})
srgb1 = gs1.makeelement(qn('a:srgbClr'), {'val': '1A1A2E'})
gs1.append(srgb1)
gsLst.append(gs1)

# Stop 2: Slightly lighter
gs2 = gsLst.makeelement(qn('a:gs'), {'pos': '100000'})
srgb2 = gs2.makeelement(qn('a:srgbClr'), {'val': '16213E'})
gs2.append(srgb2)
gsLst.append(gs2)

gradFill.append(gsLst)

# Linear direction (top to bottom)
lin = gradFill.makeelement(qn('a:lin'), {'ang': '5400000', 'scaled': '1'})
gradFill.append(lin)
bgPr.append(gradFill)

# Image background
from pptx.util import Emu
slide.background.fill.solid()  # Reset
# For image backgrounds, add as a full-slide image instead:
slide.shapes.add_picture("bg.png", 0, 0, prs.slide_width, prs.slide_height)
```

---

## Images

```python
# From file path
slide.shapes.add_picture(
    "image.png",
    Inches(1),    # left
    Inches(1),    # top
    Inches(5),    # width
    Inches(3)     # height
)

# From URL (download first)
import urllib.request
urllib.request.urlretrieve("https://example.com/img.png", "/tmp/img.png")
slide.shapes.add_picture("/tmp/img.png", Inches(1), Inches(1), Inches(5), Inches(3))

# From bytes/BytesIO
from io import BytesIO
image_stream = BytesIO(image_bytes)
slide.shapes.add_picture(image_stream, Inches(1), Inches(1), Inches(5), Inches(3))

# Preserve aspect ratio (specify only width OR height)
pic = slide.shapes.add_picture("image.png", Inches(1), Inches(1), width=Inches(5))
# Height auto-calculated from aspect ratio
```

### Image Sizing Helper

```python
from PIL import Image

def add_image_contained(slide, image_path, x, y, max_w, max_h):
    """Add image contained within bounds, preserving aspect ratio."""
    img = Image.open(image_path)
    img_w, img_h = img.size
    aspect = img_w / img_h

    # Calculate dimensions to fit within bounds
    if (max_w / max_h) > aspect:
        # Height-constrained
        height = max_h
        width = height * aspect
    else:
        # Width-constrained
        width = max_w
        height = width / aspect

    # Center within bounds
    offset_x = (max_w - width) / 2
    offset_y = (max_h - height) / 2

    slide.shapes.add_picture(
        image_path,
        Inches(x + offset_x),
        Inches(y + offset_y),
        Inches(width),
        Inches(height)
    )
```

---

## Charts

```python
from pptx.chart.data import CategoryChartData, ChartData
from pptx.enum.chart import XL_CHART_TYPE

# Bar chart
chart_data = CategoryChartData()
chart_data.categories = ['Q1', 'Q2', 'Q3', 'Q4']
chart_data.add_series('Revenue ($M)', (4.5, 5.5, 6.2, 7.1))

chart_frame = slide.shapes.add_chart(
    XL_CHART_TYPE.COLUMN_CLUSTERED,
    Inches(1), Inches(1.5), Inches(8), Inches(4.5),
    chart_data
)
chart = chart_frame.chart
chart.has_legend = False

# Style the chart
plot = chart.plots[0]
plot.gap_width = 120  # Bar spacing

# Color the bars
series = chart.series[0]
series.format.fill.solid()
series.format.fill.fore_color.rgb = RGBColor(0x02, 0xC3, 0x9A)

# Line chart
chart_data = CategoryChartData()
chart_data.categories = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun']
chart_data.add_series('Users', (1200, 1800, 2400, 3100, 4200, 5800))

chart_frame = slide.shapes.add_chart(
    XL_CHART_TYPE.LINE,
    Inches(1), Inches(1.5), Inches(8), Inches(4.5),
    chart_data
)

# Pie chart
chart_data = CategoryChartData()
chart_data.categories = ['Product A', 'Product B', 'Product C']
chart_data.add_series('Revenue Share', (45, 35, 20))

chart_frame = slide.shapes.add_chart(
    XL_CHART_TYPE.PIE,
    Inches(4), Inches(1.5), Inches(5), Inches(4.5),
    chart_data
)
chart = chart_frame.chart
chart.has_legend = True
```

### Chart Styling Tips

```python
# Remove chart title
chart.has_title = False

# Style value axis
value_axis = chart.value_axis
value_axis.has_major_gridlines = True
value_axis.major_gridlines.format.line.color.rgb = RGBColor(0xE2, 0xE8, 0xF0)
value_axis.format.line.color.rgb = RGBColor(0xE2, 0xE8, 0xF0)

# Style category axis
category_axis = chart.category_axis
category_axis.format.line.color.rgb = RGBColor(0xE2, 0xE8, 0xF0)

# Data labels
plot = chart.plots[0]
plot.has_data_labels = True
data_labels = plot.data_labels
data_labels.font.size = Pt(10)
data_labels.font.color.rgb = RGBColor(0x33, 0x33, 0x33)
```

---

## Tables

```python
# Add table
rows, cols = 4, 3
table_shape = slide.shapes.add_table(
    rows, cols,
    Inches(1), Inches(1.5),   # position
    Inches(10), Inches(3)     # size
)
table = table_shape.table

# Set column widths
table.columns[0].width = Inches(4)
table.columns[1].width = Inches(3)
table.columns[2].width = Inches(3)

# Header row
headers = ["Product", "Revenue ($M)", "Growth"]
for i, header in enumerate(headers):
    cell = table.cell(0, i)
    cell.text = header
    cell.fill.solid()
    cell.fill.fore_color.rgb = RGBColor(0x1A, 0x1A, 0x2E)
    p = cell.text_frame.paragraphs[0]
    p.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
    p.font.bold = True
    p.font.size = Pt(14)

# Data rows
data = [
    ["Product A", "$18.9M", "+142%"],
    ["Product B", "$14.7M", "+98%"],
    ["Product C", "$8.7M", "+156%"],
]
for row_idx, row_data in enumerate(data, start=1):
    for col_idx, value in enumerate(row_data):
        cell = table.cell(row_idx, col_idx)
        cell.text = value
        p = cell.text_frame.paragraphs[0]
        p.font.size = Pt(13)
        p.font.name = "Calibri"
        # Alternating row colors
        if row_idx % 2 == 0:
            cell.fill.solid()
            cell.fill.fore_color.rgb = RGBColor(0xF5, 0xF5, 0xF7)
```

---

## Templates

### Loading a Template

```python
# Load existing template
prs = Presentation("/data/openclaw/templates/brand-template.pptx")

# List available layouts
for i, layout in enumerate(prs.slide_layouts):
    print(f"Layout {i}: {layout.name}")

# List placeholders in a layout
layout = prs.slide_layouts[0]
for ph in layout.placeholders:
    print(f"  Placeholder {ph.placeholder_format.idx}: {ph.name} ({ph.width}x{ph.height})")
```

### Populating Placeholders

```python
slide = prs.slides.add_slide(prs.slide_layouts[0])

# Access by index
title_ph = slide.placeholders[0]
title_ph.text = "My Title"

subtitle_ph = slide.placeholders[1]
subtitle_ph.text = "Subtitle here"

# Format placeholder text
for paragraph in title_ph.text_frame.paragraphs:
    paragraph.font.size = Pt(40)
    paragraph.font.bold = True
```

---

## Utility Functions

### Reusable Card Component

```python
def add_card(slide, x, y, w, h, title, body, palette,
             title_size=20, body_size=14):
    """Add a styled card with title and body text."""
    # Card background
    card = slide.shapes.add_shape(
        MSO_SHAPE.ROUNDED_RECTANGLE,
        Inches(x), Inches(y), Inches(w), Inches(h)
    )
    card.fill.solid()
    card.fill.fore_color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
    card.line.color.rgb = RGBColor(0xE8, 0xE8, 0xE8)
    card.line.width = Pt(0.5)

    # Accent bar at top
    accent = slide.shapes.add_shape(
        MSO_SHAPE.RECTANGLE,
        Inches(x), Inches(y), Inches(w), Inches(0.06)
    )
    accent.fill.solid()
    accent.fill.fore_color.rgb = palette["accent"]
    accent.line.fill.background()

    # Title
    add_text(slide, title, x + 0.25, y + 0.3, w - 0.5, 0.5,
             font_size=title_size, bold=True,
             color=palette["text_dark"])

    # Body
    add_text(slide, body, x + 0.25, y + 0.9, w - 0.5, h - 1.2,
             font_size=body_size, color=palette["text_muted"])
```

### Reusable Metric Callout

```python
def add_metric(slide, x, y, value, label, palette,
               value_size=48, label_size=14):
    """Add a large number with label below."""
    add_text(slide, value, x, y, 4, 1,
             font_size=value_size, bold=True,
             color=palette["accent"], font_name="Calibri")
    add_text(slide, label, x, y + 0.9, 4, 0.5,
             font_size=label_size, color=palette["text_muted"])
```

### Color Overlay for Image Backgrounds

```python
def add_color_overlay(slide, color_rgb, opacity_pct=60):
    """Add a semi-transparent color overlay on top of an image background."""
    overlay = slide.shapes.add_shape(
        MSO_SHAPE.RECTANGLE,
        0, 0, prs.slide_width, prs.slide_height
    )
    overlay.fill.solid()
    overlay.fill.fore_color.rgb = color_rgb
    overlay.line.fill.background()

    # Set transparency via XML
    from pptx.oxml.ns import qn
    solidFill = overlay._element.spPr.solidFill
    srgbClr = solidFill.find(qn('a:srgbClr'))
    alpha = srgbClr.makeelement(qn('a:alpha'), {
        'val': str((100 - opacity_pct) * 1000)
    })
    srgbClr.append(alpha)
```

---

## Common Pitfalls

1. **Units matter**: Always use `Inches()`, `Pt()`, `Cm()`, or `Emu()` — never raw numbers
2. **RGBColor takes integers**: `RGBColor(0x1A, 0x1A, 0x2E)` not `RGBColor("1A1A2E")`
3. **First paragraph already exists**: `tf.paragraphs[0]` is always there, use `tf.add_paragraph()` for additional
4. **Blank layout = index 6**: Don't assume index 0 is blank
5. **slide_layouts[6]** can vary by template — verify with `layout.name`
6. **Word wrap defaults to off**: Always set `tf.word_wrap = True`
7. **No undo**: Operations modify the presentation in place — save to a new file if you want to keep the original
8. **Font availability**: Stick to fonts available on both Windows and Google Slides (Calibri, Arial, Georgia, Trebuchet MS)
9. **Google Slides conversion**: Gradients via XML work but may render slightly differently in Google Slides. Solid colors are safest.
10. **Shape ordering**: Shapes added later appear on top. Add backgrounds first, then foreground elements.

---

## Quick Reference

- **Positioning**: All in inches with `Inches()`. Origin (0,0) is top-left of slide.
- **Fonts**: `Pt()` for font sizes. Common: 44pt title, 20pt header, 16pt body, 12pt caption.
- **Colors**: `RGBColor(r, g, b)` with integer values 0-255, or hex: `RGBColor(0xFF, 0x00, 0x00)`
- **Shapes**: `MSO_SHAPE.RECTANGLE`, `ROUNDED_RECTANGLE`, `OVAL`, `TRIANGLE`, etc.
- **Alignment**: `PP_ALIGN.LEFT`, `PP_ALIGN.CENTER`, `PP_ALIGN.RIGHT`
- **Charts**: `XL_CHART_TYPE.COLUMN_CLUSTERED`, `LINE`, `PIE`, `DOUGHNUT`, `BAR_CLUSTERED`
