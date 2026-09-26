"""Public privacy notice at /privacy, rendered from the repo's PRIVACY.md.

The apps link here (Settings → Privacy policy, and the passenger note points
at /privacy#passengers), so the notice must be reachable without signing in.
PRIVACY.md stays the single source: the Docker image copies it to /app, the
same place relative to the package as the repo root is in a checkout.
"""

import re
from functools import lru_cache
from pathlib import Path

import markdown
from fastapi import APIRouter, HTTPException
from fastapi.responses import HTMLResponse

router = APIRouter()

PRIVACY_MD = Path(__file__).resolve().parents[3] / "PRIVACY.md"
REPO_BLOB = "https://github.com/roznet/flyfun-forms/blob/main/"

_PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>FlightForms Privacy</title>
<style>
:root {{ --bg: #ffffff; --fg: #1d1d1f; --muted: #6e6e73; --rule: #d2d2d7; --link: #0066cc; --code: #f5f5f7; }}
@media (prefers-color-scheme: dark) {{
  :root {{ --bg: #111113; --fg: #f5f5f7; --muted: #a1a1a6; --rule: #3a3a3c; --link: #4da3ff; --code: #1c1c1e; }}
}}
body {{ margin: 0; background: var(--bg); color: var(--fg);
  font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }}
main {{ max-width: 44rem; margin: 0 auto; padding: 2rem 16px 4rem; }}
h1, h2, h3 {{ line-height: 1.25; }}
h2 {{ margin-top: 2.5rem; padding-top: 1rem; border-top: 1px solid var(--rule); }}
a {{ color: var(--link); }}
code {{ background: var(--code); padding: 0.1em 0.3em; border-radius: 4px; font-size: 0.9em; }}
table {{ border-collapse: collapse; width: 100%; display: block; overflow-x: auto; }}
th, td {{ text-align: left; padding: 0.4rem 0.6rem; border-bottom: 1px solid var(--rule); vertical-align: top; }}
blockquote {{ margin: 1rem 0; padding: 0.5rem 1rem; border-left: 3px solid var(--rule); color: var(--muted); }}
</style>
</head>
<body><main>
{body}
</main></body>
</html>
"""


def _absolutise_links(html: str) -> str:
    """Point repo-relative links (SECURITY.md, legal/…) at GitHub."""
    return re.sub(
        r'href="(?!https?:|mailto:|#)([^"]+)"',
        lambda m: f'href="{REPO_BLOB}{m.group(1).lstrip("./")}"',
        html,
    )


@lru_cache(maxsize=1)
def render_privacy_page() -> str:
    text = PRIVACY_MD.read_text(encoding="utf-8")
    body = markdown.markdown(text, extensions=["tables", "toc"])
    return _PAGE.format(body=_absolutise_links(body))


@router.get("/privacy", response_class=HTMLResponse, include_in_schema=False)
def privacy():
    try:
        return HTMLResponse(render_privacy_page())
    except FileNotFoundError:
        # Image built without PRIVACY.md — fail visibly rather than serve nothing
        raise HTTPException(status_code=500, detail="Privacy notice unavailable") from None

