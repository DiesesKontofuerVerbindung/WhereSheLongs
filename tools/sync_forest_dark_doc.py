#!/usr/bin/env python3
"""Generate dialogue JSON from forest_dark_doc.txt sections."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOC = Path(__file__).resolve().parent / "forest_dark_doc.txt"


def parse_doc() -> list[str]:
    return [ln.strip() for ln in DOC.read_text(encoding="utf-8").splitlines() if ln.strip()]


def is_skip(line: str) -> bool:
    if line.startswith("\u300a") or line.startswith("\u524d\u60c5") or line.startswith("\u5199\u7ed9"):
        return True
    if re.match(r"^\d+[、.]", line):
        return True
    if line.startswith("\u3010") and (
        "\u6a21\u5757" in line
        or "\u8df3\u8fc7" in line
        or "\u73af\u5883\u80cc\u666f" in line
        or "\u4eba\u7269\u5267\u60c5" in line
        or "\u6eba\u6c34" in line
        or "\u5267\u60c5\u56fe" in line
    ):
        return True
    if line.startswith("\uff08\u6280\u672f\uff09") or line.startswith("\uff08\u548c\u4e0b\u4e00\u7ae0"):
        return True
    if "\u4f18\u5148\u7ea7" in line or "Codex Implementation" in line:
        return True
    if line.startswith("\u505a\u4e00\u4e2abutton") or line.startswith("\u5982\u679c\u9009\u62e9") or line.startswith("\u5982\u679c\u73a9\u5bb6"):
        return True
    if line.startswith("\u73af\u5883\u80cc\u666f\u56fe") and "\u8fc7\u6e21" in line:
        return True
    if line in (
        "\u4ed6\u6ca1\u6709\u518d\u95ee\u3002",
        "\u53ea\u662f\u671d\u7740\u53f3\u8fb9\u7684\u8def\u8dd1\u4e86\u8d77\u6765",
        "\u3010\u8d70/\u4e0d\u8d70\uff1f\u3011",
        "\u3010\u8fdb\u5165\u8dd1\u9177\u6e38\u620f\uff0c\u8fd9\u91cc\u76f4\u63a5\u8df3\u8fc7\u3011",
        "\u3010\u7011\u5e03\u4e0b\u6a21\u5757\uff0c\u8fd9\u91cc\u5148\u8df3\u8fc7\u3011",
        "\u3010\u6253\u5b57\u6a21\u5757\uff0c\u8fd9\u91cc\u5148\u8df3\u8fc7\u3011",
        "\u3010\u8df3\u77f3\u5934\u6a21\u5757\uff0c\u8fd9\u91cc\u5148\u8df3\u8fc7\u3011",
        "\u3010\u653e\u661f\u661f\u6a21\u5757\uff0c\u8fd9\u91cc\u5148\u8df3\u8fc7\u3011",
        "\u3010\u6cbf\u7528\u4e3b\u89c2\u5185\u5fc3\u80cc\u666f\u56fe0\u3011",
        "\u3010\u653e\u795e\u79d8\u5973\u5b69\u7684\u7acb\u7ed8\u3011",
        "\u3010\u5267\u60c5\u56fe-\u624b",
        "\u3010\u7728\u773c\u4e92\u52a8\u6a21\u5757\u3011",
        "\u3010\u5267\u60c5\u56fe-\u4e24\u4e2a\u624b\u677e\u5f00\u7684\u7279\u5199\u3011",
    ):
        return True
    if line.startswith("\u3010") and "\u8282\u70b9" in line:
        return True
    if "\u8df3\u77f3\u5934\u5207\u6362" in line:
        return True
    if line.startswith("\u3010\u5c0f\u51cc2"):
        return True
    if line.startswith("\u65c1\u8fb9\uff1a"):
        return True
    if line.startswith("\u505c") and "s" in line:
        return True
    if line.startswith("\u95ed\u773c\u4ea4\u4e92"):
        return True
    if re.match(r"^\u5f88\u4e45\u4ee5\u540e", line):
        return False
    return False


def parse_line(raw: str) -> dict | None:
    if is_skip(raw):
        return None
    s = raw.strip()
    m = re.match(r"^(\u5c0f\u51cc|\u963f\u9ea6|\u5973\u5b69|\u65c1\u767d)[\uff1a:](.*)$", s)
    if m:
        speaker = "\u795e\u79d8\u5973\u5b69" if m.group(1) == "\u5973\u5b69" else m.group(1)
        text = m.group(2).strip()
        if speaker == "\u963f\u9ea6" and text.startswith("\u963f\u9ea6\uff1a"):
            text = text[3:].strip()
        return {"speaker": speaker, "text": text}
    m = re.match(r"^(\u5c0f\u51cc|\u963f\u9ea6|\u5973\u5b69)[\uff08(]([^\uff09)]+)[\uff09)](.*)$", s)
    if m:
        speaker = "\u795e\u79d8\u5973\u5b69" if m.group(1) == "\u5973\u5b69" else m.group(1)
        tag = m.group(2).strip()
        rest = m.group(3).strip()
        if rest.startswith("\uff1a") or rest.startswith(":"):
            rest = rest[1:].strip()
        text = f"\uff08{tag}\uff09{rest}" if rest else f"\uff08{tag}\uff09"
        return {"speaker": speaker, "text": text}
    m = re.match(r"^(\u5c0f\u51cc|\u963f\u9ea6|\u5973\u5b69)([\uff1b;].*)$", s)
    if m:
        speaker = "\u795e\u79d8\u5973\u5b69" if m.group(1) == "\u5973\u5b69" else m.group(1)
        return {"speaker": speaker, "text": m.group(2).lstrip("\uff1b;").strip()}
    if len(s) >= 2 and s[0] == "\u201c" and s.endswith("\u3002"):
        return {"speaker": "\u65c1\u767d", "text": s}
    m = re.match(r"^\u5973\u5b69([^（(\uff1a:]+)[\uff1a:](.*)$", s)
    if m:
        lead = m.group(1).strip()
        rest = m.group(2).strip()
        if lead:
            text = f"\uff08{lead}\uff09{rest}" if rest else f"\uff08{lead}\uff09"
        else:
            text = rest
        return {"speaker": "\u795e\u79d8\u5973\u5b69", "text": text}
    m = re.match(r"^\u963f\u9ea6([^（(\uff1a:]+)[\uff1a:](.*)$", s)
    if m:
        lead = m.group(1).strip()
        rest = m.group(2).strip()
        text = f"\uff08{lead}\uff09{rest}" if lead else rest
        return {"speaker": "\u963f\u9ea6", "text": text}
    if re.match(r"^\u5f88\u4e45\u4ee5\u540e", s):
        parts = re.split(r"[\uff1a:]", s, maxsplit=1)
        if len(parts) == 2:
            return {"speaker": "\u5c0f\u51cc", "text": parts[1].strip()}
    if s.startswith("\u5973\u5b69\u7a81\u7136\u95ee\uff1a"):
        return {"speaker": "\u795e\u79d8\u5973\u5b69", "text": s.split("\uff1a", 1)[1].strip()}
    if s.startswith("\u5973\u5b69\u505c\u4e86\u4e00\u4e0b"):
        return {"speaker": "\u795e\u79d8\u5973\u5b69", "text": s.split("\uff1a", 1)[1].strip()}
    if s.startswith("\u5973\u5b69\u6ca1\u6709\u56de\u7b54\uff0c\u53ea\u662f"):
        return {"speaker": "\u795e\u79d8\u5973\u5b69", "text": s.split("\uff1a", 1)[1].strip()}
    if s.startswith("\u5979\u770b\u7740\u5973\u5b69\u3002"):
        return {"speaker": "\u65c1\u767d", "text": s}
    if s.startswith("\u4e0d\u7a33\u5b9a\u7684\u4e16\u754c"):
        return {"speaker": "\u65c1\u767d", "text": s}
    return {"speaker": "\u65c1\u767d", "text": s}


def clean_lines(lines: list[dict]) -> list[dict]:
    out = []
    for ln in lines:
        if "text" not in ln:
            out.append(ln)
            continue
        text = ln["text"]
        text = re.sub(r"\s*\u505c\d+-\d+s\s*", "", text)
        if ln.get("speaker") == "\u5c0f\u51cc" and text.startswith("("):
            text = text.replace("(", "\uff08", 1).replace(")", "\uff09", 1)
        out.append({**ln, "text": text})
    return out


def section(lines: list[str], start: int, end: int) -> list[dict]:
    out = []
    for raw in lines[start - 1 : end]:
        item = parse_line(raw)
        if item:
            out.append(item)
    return clean_lines(out)


def write_json(name: str, lines: list[dict], extra: dict | None = None):
    data = {"id": name, "lines": lines}
    if extra:
        data.update(extra)
    path = ROOT / "data" / "dialogue" / f"{name}.json"
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {path.name}: {len(lines)} lines")


def main():
    lines = parse_doc()
    write_json("part1_end", section(lines, 50, 50))
    write_json("part2_waterfall", section(lines, 86, 96))
    stream = section(lines, 103, 117)
    for i, ln in enumerate(stream):
        if ln.get("speaker") == "\u5c0f\u51cc" and ln.get("text") == "\u56e0\u4e3a\u2026\u2026\u3010\u8fd9\u91cc\u8bbe\u7f6e\u6587\u672c\u6846\uff0c\u8ba9\u73a9\u5bb6\u81ea\u5df1\u6253\u5b57\u3011":
            stream[i] = {"speaker": "\u5c0f\u51cc", "text": "\u56e0\u4e3a\u2026\u2026"}
            stream.insert(
                i + 1,
                {
                    "action": "text_input",
                    "prompt": "\u8bf7\u8f93\u5165\uff1a",
                    "var_key": "custom_player_text",
                    "placeholder": "\u4e3a\u4ec0\u4e48\u4eba\u4e0d\u80fd\u60f3\u505a\u4ec0\u4e48\u5c31\u505a\u4ec0\u4e48\uff1f",
                },
            )
            stream.insert(i + 2, {"speaker": "\u5c0f\u51cc", "text": "{custom_player_text}"})
            break
    write_json("part2_stream", stream)
    write_json("part2_continue", section(lines, 120, 121))
    write_json("part3_lake_end", section(lines, 148, 148))
    write_json("part4_mystery_girl", section(lines, 153, 311))


if __name__ == "__main__":
    main()
