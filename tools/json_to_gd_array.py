#!/usr/bin/env python3
"""Emit GDScript dialogue array literal from parsed JSON."""
import json
import sys
from pathlib import Path

def to_gd(lines: list[dict]) -> str:
    parts = []
    for line in lines:
        items = []
        for k, v in line.items():
            if isinstance(v, str):
                esc = v.replace("\\", "\\\\").replace('"', '\\"')
                items.append(f'"{k}": "{esc}"')
            else:
                items.append(f'"{k}": {json.dumps(v, ensure_ascii=False)}')
        parts.append("\t\t{" + ", ".join(items) + "}")
    return "[\n" + ",\n".join(parts) + "\n\t]"


if __name__ == "__main__":
    data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    print(to_gd(data))
