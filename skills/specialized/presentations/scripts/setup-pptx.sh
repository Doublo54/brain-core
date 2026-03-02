#!/bin/bash
# Setup script for python-pptx + markitdown in agent sandbox
# Installs all dependencies for both creating and reading PPTX files

set -e

echo "=== Installing PPTX skill dependencies ==="

# Install python-pptx (creation), Pillow (images), markitdown (reading/extraction)
pip install python-pptx Pillow "markitdown[pptx]" --break-system-packages --quiet 2>/dev/null || \
pip install python-pptx Pillow "markitdown[pptx]" --quiet 2>/dev/null || \
pip3 install python-pptx Pillow "markitdown[pptx]" --break-system-packages --quiet

# Verify installation
python3 -c "
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN
from pptx.enum.shapes import MSO_SHAPE
print('python-pptx installed and all imports working')

# Quick smoke test: create a minimal presentation
prs = Presentation()
prs.slide_width = Inches(13.333)
prs.slide_height = Inches(7.5)
slide = prs.slides.add_slide(prs.slide_layouts[6])
slide.background.fill.solid()
slide.background.fill.fore_color.rgb = RGBColor(0x1A, 0x1A, 0x2E)
txBox = slide.shapes.add_textbox(Inches(1), Inches(2), Inches(10), Inches(2))
tf = txBox.text_frame
p = tf.paragraphs[0]
p.text = 'Setup Verification'
p.font.size = Pt(36)
p.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
prs.save('/tmp/pptx-verify.pptx')
print('Smoke test passed: /tmp/pptx-verify.pptx created')
"

# Verify markitdown
python3 -c "
from markitdown import MarkItDown
md = MarkItDown()
result = md.convert('/tmp/pptx-verify.pptx')
assert 'Setup Verification' in result.text_content
print('markitdown installed and reading PPTX correctly')
"

# Cleanup
rm -f /tmp/pptx-verify.pptx

echo "=== PPTX skill setup complete (create + read) ==="
