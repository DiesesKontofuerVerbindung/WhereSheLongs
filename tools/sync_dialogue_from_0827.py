#!/usr/bin/env python3
"""Generate or verify the 0827 dialogue sync without changing source wording."""

import argparse
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SRC = Path(__file__).resolve().parent / "0827_extracted.txt"
OUT = Path(__file__).resolve().parent / "0827_parsed"

JSON_SECTIONS = {
    "chapter1_prologue": (1, 1),
    "chapter2_prologue": (3, 3),
    "part1_end": (68, 70),
    "part2_waterfall": (108, 118),
    "part2_stream": (122, 138),
    "part2_continue": None,
    "part3_lake_end": (172, 172),
    "part4_mystery_girl": (174, 335),
    "demo_end": (337, 337),
}

INLINE_SECTIONS = {
    "forest_dark": (22, 67),
    "forest_path": (72, 106),
    "stream_area": (120, 121),
    "lake_area": (141, 170),
}

INLINE_PATHS = {
    "forest_dark": ROOT / "levels" / "maps" / "forest_dark.gd",
    "forest_path": ROOT / "levels" / "maps" / "forest_path.gd",
    "stream_area": ROOT / "levels" / "maps" / "stream_area.gd",
    "lake_area": ROOT / "levels" / "maps" / "lake_area.gd",
}

TITLE_LINES = {1, 3, 5, 337}
SPEAKER_RE = re.compile(r"^(小凌|阿麦|女孩)：(.*)$")
INLINE_NOTE_RE = re.compile(r"【[^】]*】")
GD_DIALOGUE_RE = re.compile(r'\{"speaker":\s*"(?:[^"\\]|\\.)*",\s*"text":\s*"(?:[^"\\]|\\.)*"\}')


def load_source() -> list[str]:
    lines = SRC.read_text(encoding="utf-8").splitlines()
    if len(lines) != 338:
        raise ValueError(f"expected 338 source lines, got {len(lines)}")
    return lines


def source_line(lines: list[str], line_number: int) -> str:
    return lines[line_number - 1].strip()


def parse_line(raw: str, line_number: int) -> dict | None:
    text = raw.strip()
    if not text or text == "//" or text.startswith("（PART "):
        return None
    if line_number in TITLE_LINES:
        return {"speaker": "旁白", "text": text, "action": "show_title"}
    text = INLINE_NOTE_RE.sub("", text).strip()
    if not text:
        return None
    match = SPEAKER_RE.match(text)
    if match:
        speaker, body = match.groups()
        return {
            "speaker": "神秘女孩" if speaker == "女孩" else speaker,
            "text": body.strip(),
        }
    return {"speaker": "旁白", "text": text}


def parse_range(lines: list[str], start: int, end: int) -> list[dict]:
    parsed: list[dict] = []
    for line_number in range(start, end + 1):
        item = parse_line(source_line(lines, line_number), line_number)
        if item is not None:
            parsed.append(item)
    return parsed


def build_dialogues(lines: list[str]) -> dict[str, dict]:
    built: dict[str, dict] = {}
    for dialogue_id, line_range in JSON_SECTIONS.items():
        parsed = [] if line_range is None else parse_range(lines, *line_range)
        built[dialogue_id] = {"id": dialogue_id, "lines": parsed}

    intro = [parse_line(source_line(lines, 5), 5)]
    intro.extend(parse_range(lines, 19, 21))
    built["wonderful_night_intro"] = {
        "id": "wonderful_night_intro",
        "lines": intro,
    }

    waterfall = built["part2_waterfall"]["lines"]
    waterfall[0]["cg"] = "waterfall"
    waterfall[-1].update({
        "cg": "dive",
        "action": "set_var",
        "key": "affection_amai",
        "value": 5,
        "op": "add",
    })

    stream = built["part2_stream"]["lines"]
    ellipsis_index = next(
        index for index, item in enumerate(stream)
        if item.get("speaker") == "小凌" and item.get("text") == "……"
    )
    stream.insert(ellipsis_index + 1, {
        "action": "text_input",
        "prompt": "请输入你想说的话：",
        "var_key": "custom_player_text",
        "placeholder": "为什么人不能想做什么就做什么？",
    })
    return built


def build_inline(lines: list[str]) -> dict[str, list[dict]]:
    return {
        name: parse_range(lines, start, end)
        for name, (start, end) in INLINE_SECTIONS.items()
    }


def write_generated(dialogues: dict[str, dict], inline: dict[str, list[dict]]) -> None:
    dialogue_dir = ROOT / "data" / "dialogue"
    for dialogue_id, data in dialogues.items():
        path = dialogue_dir / f"{dialogue_id}.json"
        path.write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"wrote {path.relative_to(ROOT)} ({len(data['lines'])} entries)")

    OUT.mkdir(exist_ok=True)
    for name, parsed in inline.items():
        path = OUT / f"{name}_inline.json"
        path.write_text(
            json.dumps(parsed, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"wrote {path.relative_to(ROOT)} ({len(parsed)} lines)")


def load_gd_dialogue(path: Path) -> list[dict]:
    source = path.read_text(encoding="utf-8")
    return [json.loads(match.group(0)) for match in GD_DIALOGUE_RE.finditer(source)]


def verify(dialogues: dict[str, dict], inline: dict[str, list[dict]]) -> None:
    failures: list[str] = []
    for dialogue_id, expected in dialogues.items():
        path = ROOT / "data" / "dialogue" / f"{dialogue_id}.json"
        actual = json.loads(path.read_text(encoding="utf-8"))
        if actual != expected:
            failures.append(f"dialogue mismatch: {path.relative_to(ROOT)}")

    for name, expected in inline.items():
        path = INLINE_PATHS[name]
        actual = load_gd_dialogue(path)
        if actual != expected:
            failures.append(
                f"inline mismatch: {path.relative_to(ROOT)} "
                f"(expected {len(expected)}, got {len(actual)})"
            )

    if failures:
        raise SystemExit("\n".join(failures))
    print("0827 dialogue verification passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify game files without writing them",
    )
    args = parser.parse_args()

    source = load_source()
    dialogues = build_dialogues(source)
    inline = build_inline(source)
    if args.check:
        verify(dialogues, inline)
    else:
        write_generated(dialogues, inline)


if __name__ == "__main__":
    main()
