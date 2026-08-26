"""Logical Checklist mapping kept separate from visual SwipeBlock objects."""

from __future__ import annotations

import config


class ChecklistMapper:
    def __init__(self) -> None:
        self.block_to_checklist = {
            f"block_{index}": f"item_{index}"
            for index in range(1, config.BLOCK_COUNT + 1)
        }
        self.items = {
            item_id: {"item_id": item_id, "label": f"Item {index}", "completed": False}
            for index, item_id in enumerate(self.block_to_checklist.values(), start=1)
        }

    @property
    def completed_count(self) -> int:
        return sum(item["completed"] for item in self.items.values())

    def complete_for_block(self, block_id: str) -> bool:
        item_id = self.block_to_checklist.get(block_id)
        if item_id is None or self.items[item_id]["completed"]:
            return False
        self.items[item_id]["completed"] = True
        return True

    def snapshot(self) -> list[dict[str, object]]:
        return [dict(item) for item in self.items.values()]

    def reset(self) -> None:
        for item in self.items.values():
            item["completed"] = False
