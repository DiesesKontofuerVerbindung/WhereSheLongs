"""Visual swipe blocks. Checklist data is intentionally kept elsewhere."""

from __future__ import annotations

from dataclasses import dataclass
import config


@dataclass
class SwipeBlock:
    block_id: str
    center_x: float
    center_y: float
    initial_x: float
    initial_y: float
    width: float
    height: float
    layer: int
    completed: bool = False
    removal_started_at: float | None = None
    removal_start_y: float | None = None

    def contains(self, x: float, y: float, margin: float = 0.0) -> bool:
        return (
            abs(x - self.center_x) <= self.width / 2 + margin
            and abs(y - self.center_y) <= self.height / 2 + margin
        )


class BlockManager:
    """Owns visual positions and the one-success-only block invariant."""

    def __init__(self) -> None:
        self.blocks: list[SwipeBlock] = [
            SwipeBlock(
                block_id=f"wood_{index + 1}",
                center_x=config.WOOD_STACK_CENTER_X + config.WOOD_STACK_X_OFFSETS[index],
                center_y=config.WOOD_STACK_BASE_Y - index * config.WOOD_STACK_LAYER_STEP,
                initial_x=config.WOOD_STACK_CENTER_X + config.WOOD_STACK_X_OFFSETS[index],
                initial_y=config.WOOD_STACK_BASE_Y - index * config.WOOD_STACK_LAYER_STEP,
                width=config.BLOCK_WIDTH,
                height=config.BLOCK_HEIGHT,
                layer=index,
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

    @property
    def top_block(self) -> SwipeBlock | None:
        """The visible top layer is the only target eligible for a new swipe."""

        available = [block for block in self.blocks if not block.completed]
        return min(available, key=lambda block: (block.center_y, -block.layer), default=None)

    def hit_test(self, x: float, y: float) -> SwipeBlock | None:
        top = self.top_block
        if top is not None and top.contains(x, y, config.BLOCK_HITBOX_MARGIN):
            return top
        return None

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

    def start_removal_animation(self, block_id: str, now: float) -> None:
        block = self.get(block_id)
        if block is not None and block.completed:
            block.removal_started_at = now
            block.removal_start_y = block.center_y

    def update_removal_animations(self, now: float) -> None:
        for block in self.blocks:
            if block.removal_started_at is None or block.removal_start_y is None:
                continue
            progress = min(1.0, max(0.0, (now - block.removal_started_at) / config.BLOCK_FLY_OUT_DURATION))
            block.center_y = block.removal_start_y + progress * (config.BLOCK_FLY_OUT_TARGET_Y - block.removal_start_y)
            if progress >= 1.0:
                block.removal_started_at = None
                block.removal_start_y = None

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
            block.removal_started_at = None
            block.removal_start_y = None
