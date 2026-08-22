"""Keep every literal Flutter API call connected to a real backend route."""

from pathlib import Path
import re

from app.main import app


ROOT = Path(__file__).resolve().parents[1]


def _shape(path: str) -> tuple[str, ...]:
    path = re.sub(r"\$\{[^}]+\}|\$[A-Za-z_][A-Za-z0-9_]*", "{}", path)
    path = path.split("?", 1)[0].rstrip("/") or "/"
    return tuple(
        "{}" if part.startswith("{") and part.endswith("}") else part
        for part in path.split("/")
    )


def test_every_literal_flutter_api_call_resolves() -> None:
    implemented = {
        (method.lower(), _shape(route.path.removeprefix("/api/v1")))
        for route in app.routes
        for method in (getattr(route, "methods", None) or set())
    }
    call = re.compile(
        r"\b(?:api|client)\."
        r"(getBytes|postForm|uploadBytes|uploadFile|get|post|put|patch|delete)"
        r"(?:<[^>]+>)?\(\s*"
        r"(['\"])(/[^'\"]+)\2",
        re.MULTILINE,
    )
    missing = []
    for path in (ROOT / "mobile/lib").rglob("*.dart"):
        source = re.sub(r"\$\{.*?\}", "{}", path.read_text())
        for match in call.finditer(source):
            raw_method, api_path = match.group(1), match.group(3)
            method = {
                "getBytes": "get",
                "postForm": "post",
                "uploadBytes": "post",
                "uploadFile": "post",
            }.get(raw_method, raw_method)
            if (method, _shape(api_path)) not in implemented:
                line = source.count("\n", 0, match.start()) + 1
                missing.append(
                    f"{path.relative_to(ROOT)}:{line}: "
                    f"{method.upper()} {api_path}"
                )
    assert missing == []
