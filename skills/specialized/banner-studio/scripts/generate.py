#!/usr/bin/env python3
"""Banner Studio — Render HTML/CSS templates to PNG via Playwright."""

import argparse
import html as html_mod
import json
import logging
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

BASE_DIR = Path(__file__).parent.parent
DEFAULT_TEMPLATES_DIR = BASE_DIR / "assets" / "templates"
DEFAULT_WIDTH = 1200
DEFAULT_HEIGHT = 675

log = logging.getLogger("banner-studio")


def load_template(template_name: str, template_dir: Path) -> str:
    template_path = template_dir / template_name
    if not template_path.exists():
        available = [f.name for f in template_dir.glob("*.html")]
        raise FileNotFoundError(
            f"Template '{template_name}' not found in {template_dir}. "
            f"Available: {available}"
        )
    return template_path.read_text()


def load_brand_colors(brand_dir: Path) -> dict:
    colors_path = brand_dir / "colors.json"
    if colors_path.exists():
        return json.loads(colors_path.read_text())
    return {}


def inject_variables(html: str, data: dict) -> str:
    for key, value in data.items():
        safe_value = html_mod.escape(str(value))
        html = html.replace(f"{{{{{key}}}}}", safe_value)
    return html


def check_unreplaced_placeholders(html: str) -> list[str]:
    import re

    return re.findall(r"\{\{(\w+)\}\}", html)


def verify_playwright() -> bool:
    result = subprocess.run(
        [sys.executable, "-c", "from playwright.sync_api import sync_playwright"],
        capture_output=True,
        text=True,
    )
    return result.returncode == 0


def render_html_to_png(html: str, width: int, height: int, output_path: str) -> None:
    with tempfile.NamedTemporaryFile(mode="w", suffix=".html", delete=False) as tmp:
        tmp.write(html)
        tmp_path = tmp.name

    render_script = f"""\
import sys
from playwright.sync_api import sync_playwright

try:
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={{"width": {width}, "height": {height}}})
        page.goto("file://{tmp_path}")
        page.wait_for_load_state("networkidle")
        page.screenshot(path="{output_path}", type="png")
        browser.close()
except Exception as e:
    print(f"Playwright render error: {{e}}", file=sys.stderr)
    sys.exit(1)
"""

    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".py", delete=False
    ) as script_tmp:
        script_tmp.write(render_script)
        script_path = script_tmp.name

    try:
        result = subprocess.run(
            [sys.executable, script_path],
            capture_output=True,
            text=True,
            timeout=60,
        )
        if result.returncode != 0:
            stderr = result.stderr.strip()
            raise RuntimeError(f"Playwright render failed: {stderr}")
    except subprocess.TimeoutExpired:
        raise RuntimeError("Playwright render timed out after 60s")
    finally:
        Path(script_path).unlink(missing_ok=True)
        Path(tmp_path).unlink(missing_ok=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Render HTML banner templates to PNG via Playwright"
    )
    parser.add_argument(
        "--template", "-t", required=True, help="Template HTML filename"
    )
    parser.add_argument(
        "--data",
        "-d",
        type=str,
        default="{}",
        help='JSON string with template variables (e.g. \'{"title": "Hello"}\')',
    )
    parser.add_argument("--output", "-o", type=str, help="Output PNG path")
    parser.add_argument(
        "--width", "-w", type=int, default=DEFAULT_WIDTH, help="Output width (px)"
    )
    parser.add_argument(
        "--height", type=int, default=DEFAULT_HEIGHT, help="Output height (px)"
    )
    parser.add_argument(
        "--template-dir",
        type=str,
        default=str(DEFAULT_TEMPLATES_DIR),
        help="Path to HTML templates directory",
    )
    parser.add_argument(
        "--brand-dir",
        type=str,
        default=None,
        help="Path to org-specific brand assets (colors.json, logos)",
    )
    return parser.parse_args()


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(levelname)s: %(message)s",
    )

    args = parse_args()

    try:
        data = json.loads(args.data)
    except json.JSONDecodeError as e:
        log.error("Invalid JSON in --data: %s", e)
        sys.exit(1)

    if not isinstance(data, dict):
        log.error("--data must be a JSON object, got %s", type(data).__name__)
        sys.exit(1)

    template_dir = Path(args.template_dir)
    if not template_dir.is_dir():
        log.error("Template directory not found: %s", template_dir)
        sys.exit(1)

    if args.brand_dir:
        brand_path = Path(args.brand_dir)
        if not brand_path.is_dir():
            log.error("Brand directory not found: %s", brand_path)
            sys.exit(1)
        brand_colors = load_brand_colors(brand_path)
        if brand_colors:
            data["brand_colors"] = json.dumps(brand_colors)
        data["brand_dir"] = str(brand_path.resolve())
        log.info("Brand assets loaded from %s", brand_path)

    try:
        template_html = load_template(args.template, template_dir)
    except FileNotFoundError as e:
        log.error("%s", e)
        sys.exit(1)

    processed_html = inject_variables(template_html, data)

    unreplaced = check_unreplaced_placeholders(processed_html)
    if unreplaced:
        log.warning("Unreplaced placeholders: %s", unreplaced)

    if args.output:
        output_path = Path(args.output)
    else:
        output_dir = Path("./output")
        output_dir.mkdir(exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        stem = Path(args.template).stem
        output_path = output_dir / f"{stem}-{timestamp}.png"

    output_path.parent.mkdir(parents=True, exist_ok=True)

    if not verify_playwright():
        log.error(
            "Playwright not available. Run: pip install playwright && playwright install chromium"
        )
        sys.exit(1)

    log.info(
        "Rendering %s (%dx%d) → %s", args.template, args.width, args.height, output_path
    )

    try:
        render_html_to_png(processed_html, args.width, args.height, str(output_path))
    except RuntimeError as e:
        log.error("%s", e)
        sys.exit(1)

    log.info("Banner generated: %s (%dx%d)", output_path, args.width, args.height)


if __name__ == "__main__":
    main()
