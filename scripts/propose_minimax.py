#!/usr/bin/env python3
"""Host-side MiniMax proposer for aura-tetris.

HTTP stays here. Soft only reads the lambda file this script writes and
gates it (set!/score/display/mutate/eval/load/shell/http are Soft's job).

Config: $MINIMAX_ENV_FILE or ~/.config/aura-build/minimax.env
  MINIMAX_API_KEY_FILE, MINIMAX_BASE_URL, MINIMAX_MODEL

Usage: propose_minimax.py OUT_PATH
Stdout stays empty. Stderr is PROPOSE_WROTE or PROPOSE_FAIL <reason>.
The API key is never printed.
"""
from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path


def _env_file() -> Path | None:
    raw = os.environ.get("MINIMAX_ENV_FILE", "").strip()
    candidates = []
    if raw:
        candidates.append(Path(raw))
    candidates.append(Path.home() / ".config" / "aura-build" / "minimax.env")
    candidates.append(Path("/home/box/.config/aura-build/minimax.env"))
    for p in candidates:
        if p.is_file():
            return p
    return None


def _parse_env(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def _read_key(env: dict[str, str], env_path: Path) -> str:
    key = os.environ.get("MINIMAX_API_KEY", "").strip()
    if key:
        return key
    file_raw = env.get("MINIMAX_API_KEY_FILE", "").strip()
    candidates = []
    if file_raw:
        candidates.append(Path(file_raw))
        candidates.append(env_path.parent / Path(file_raw).name)
    candidates.append(env_path.parent / "minimax_api_key")
    for p in candidates:
        if p.is_file():
            return p.read_text(encoding="utf-8").strip()
    return ""


def _redact(text: str, key: str) -> str:
    if key and key in text:
        text = text.replace(key, "[redacted]")
    return text


def _extract_lambda(text: str) -> str:
    if not text:
        return ""
    fence = re.search(r"```(?:aura|scheme|lisp)?\s*([\s\S]*?)```", text, re.I)
    body = fence.group(1) if fence else text
    m = re.search(r"\(lambda\s*\((?:row|board)\s+piece\)[\s\S]*\)\s*$", body.strip())
    if not m:
        m = re.search(r"\(lambda\s*\((?:row|board)\s+piece\)[\s\S]*\)", body)
    if not m:
        return ""
    line = " ".join(m.group(0).split())
    return line


def main() -> int:
    if len(sys.argv) != 2:
        print("PROPOSE_FAIL usage", file=sys.stderr)
        return 2
    out = Path(sys.argv[1])
    env_path = _env_file()
    if env_path is None:
        print("PROPOSE_FAIL no_env", file=sys.stderr)
        return 1
    env = _parse_env(env_path)
    key = _read_key(env, env_path)
    if not key:
        print("PROPOSE_FAIL no_key", file=sys.stderr)
        return 1
    base = (
        os.environ.get("MINIMAX_BASE_URL", "").strip()
        or env.get("MINIMAX_BASE_URL", "").strip()
        or "https://api.minimaxi.com/v1"
    ).rstrip("/")
    model = (
        os.environ.get("MINIMAX_MODEL", "").strip()
        or env.get("MINIMAX_MODEL", "").strip()
        or "MiniMax-M3"
    )
    prompt = (
        "Return ONLY one Aura line of the form "
        "(lambda (row piece) <expr>). "
        "row is the landing row (larger is deeper), piece is 0..6. "
        "The expr must return a number; higher means a better landing. "
        "Do not use set!. Do not mention score, lines, display, mutate, "
        "eval, load, shell, or http. No markdown."
    )
    body = {
        "model": model,
        "messages": [
            {"role": "system", "content": "You output a single Aura lambda and nothing else."},
            {"role": "user", "content": prompt},
        ],
        "temperature": 0.2,
        "max_tokens": 256,
        "thinking": {"type": "disabled"},
    }
    req = urllib.request.Request(
        f"{base}/chat/completions",
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        err = exc.read().decode("utf-8", errors="replace")[:300]
        print("PROPOSE_FAIL http_" + str(exc.code) + " " + _redact(err, key), file=sys.stderr)
        return 1
    except Exception as exc:  # noqa: BLE001
        print("PROPOSE_FAIL " + _redact(type(exc).__name__, key), file=sys.stderr)
        return 1
    try:
        content = str(payload["choices"][0]["message"]["content"] or "")
    except (KeyError, IndexError, TypeError):
        print("PROPOSE_FAIL no_content", file=sys.stderr)
        return 1
    lam = _extract_lambda(content)
    if not lam.startswith("(lambda"):
        print("PROPOSE_FAIL no_lambda", file=sys.stderr)
        return 1
    out.write_text(lam + "\n", encoding="utf-8")
    print("PROPOSE_WROTE", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
