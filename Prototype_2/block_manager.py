"""Visual swipe blocks. Checklist data is intentionally kept elsewhere."""

from __future__ import annotations

from dataclasses import dataclass
from math import hypot

import config


@dataclass
class SwipeBlock:
    block_id: str
    center_x: float
    center_y: float
    initial_x: float
    initial_y: float
    completed: bool = False

    def contains(self, x: float, y: float, margin: float = 0.0) -> bool:
        return (
            abs(x - self.center_x) <= config.BLOCK_WIDTH / 2 + margin
            and abs(y - self.center_y) <= config.BLOCK_HEIGHT / 2 + margin
        )


class BlockManager:
    """Owns visual positions and the one-success-only block invariant."""

    def __init__(self) -> None:
        total_width = config.BLOCK_COUNT * config.BLOCK_WIDTH + (config.BLOCK_COUNT - 1) * config.BLOCK_GAP
        first_x = (config.WINDOW_WIDTH - total_width) / 2 + config.BLOCK_WIDTH / 2
        self.blocks: list[SwipeBlock] = [
            SwipeBlock(
                block_id=f"block_{index + 1}",
                center_x=first_x + index * (config.BLOCK_WIDTH + config.BLOCK_GAP),
                center_y=config.BLOCK_CENTER_Y,
                initial_x=first_x + index * (config.BLOCK_WIDTH + config.BLOCK_GAP),
                initial_y=config.BLOCK_CENTER_Y,
            )
            for index in range(config.BLOCK_COUNT)
        ]

    @property
    def completed_count(self) -> int:
        return sum(block.completed for block in self.blocks)

    @property
    def all_completed(self) -> bool:
        return self.completed_count == len(self.blocks)

    def get(self, block_id: str | None) -> SwipeBlock | None:
        return next((block for block in self.blocks if block.block_id == block_id), None)

    def hit_test(self, x: float, y: float) -> SwipeBlock | None:
        candidates = [
            block for block in self.blocks
            if not block.completed and block.contains(x, y, config.BLOCK_HITBOX_MARGIN)
        ]
        return min(candidates, key=lambda block: hypot(x - block.center_x, y - block.center_y), default=None)

    def move_vertical(self, block_id: str, center_y: float) -> None:
        block = self.get(block_id)
        if block is not None and not block.completed:
            block.center_y = float(center_y)

    def mark_completed(self, block_id: str) -> bool:
        block = self.get(block_id)
        if block is None or block.completed:
            return False
        block.completed = True
        return True

    def restore(self, block_id: str | None) -> None:
        block = self.get(block_id)
        if block is not None and not block.completed:
            block.center_x = block.initial_x
            block.center_y = block.initial_y

    def reset_uncompleted_positions(self) -> None:
        for block in self.blocks:
            self.restore(block.block_id)

    def reset_all(self) -> None:
        for block in self.blocks:
            block.completed = False
            block.center_x = block.initial_x
            block.center_y = block.initial_y
