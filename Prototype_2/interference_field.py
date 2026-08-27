"""Unicode letter entities that visualize mixed voices being fanned apart."""

from __future__ import annotations

from dataclasses import dataclass
from math import sin
from pathlib import Path
from random import Random

import numpy as np
from PIL import Image, ImageDraw, ImageFont

import config


LATIN_GLYPHS = tuple("ABCDEFGHIKLMNOPRSTUVXYZ")
CYRILLIC_GLYPHS = tuple("БГДЖЗЛФЦЧШЩЭЮЯ")


@dataclass
class LetterEntity:
    glyph: str
    x: float
    y: float
    side: int
    size: int
    color: tuple[int, int, int]
    phase: float
    velocity_x: float = 0.0
    velocity_y: float = 0.0
    dispersed: bool = False


class InterferenceField:
    """Maintain a deterministic central cluster and push it to both sides."""

    _colors = (
        (235, 104, 115),
        (112, 168, 255),
        (202, 122, 245),
        (245, 184, 92),
        (116, 218, 181),
    )

    def __init__(
        self,
        width: int = config.WINDOW_WIDTH,
        height: int = config.WINDOW_HEIGHT,
        seed: int = config.INTERFERENCE_RANDOM_SEED,
    ) -> None:
        self.width = int(width)
        self.height = int(height)
        self.seed = int(seed)
        self.entities: list[LetterEntity] = []
        self.elapsed = 0.0
        self._last_sweep_count = 0
        self._font_cache: dict[int, ImageFont.FreeTypeFont | ImageFont.ImageFont] = {}
        self.reset()

    @property
    def dispersed_count(self) -> int:
        return sum(entity.dispersed for entity in self.entities)

    @property
    def dispersed_ratio(self) -> float:
        return 0.0 if not self.entities else self.dispersed_count / len(self.entities)

    def reset(self) -> None:
        random = Random(self.seed)
        glyphs = list(LATIN_GLYPHS + CYRILLIC_GLYPHS)
        random.shuffle(glyphs)
        self.entities = []
        for index in range(config.INTERFERENCE_ENTITY_COUNT):
            glyph = glyphs[index % len(glyphs)]
            x = config.INTERFERENCE_CENTER_X + random.uniform(
                -config.INTERFERENCE_CLUSTER_WIDTH / 2,
                config.INTERFERENCE_CLUSTER_WIDTH / 2,
            )
            y = config.INTERFERENCE_CENTER_Y + random.uniform(
                -config.INTERFERENCE_CLUSTER_HEIGHT / 2,
                config.INTERFERENCE_CLUSTER_HEIGHT / 2,
            )
            self.entities.append(LetterEntity(
                glyph=glyph,
                x=x,
                y=y,
                side=-1 if index % 2 == 0 else 1,
                size=random.randint(config.INTERFERENCE_MIN_FONT_SIZE, config.INTERFERENCE_MAX_FONT_SIZE),
                color=random.choice(self._colors),
                phase=random.uniform(0.0, 6.283185307),
            ))
        self.elapsed = 0.0
        self._last_sweep_count = 0

    def update(self, delta_time: float, fan_strength: float, direction: str, sweep_count: int) -> None:
        delta_time = max(0.0, min(0.10, float(delta_time)))
        strength = max(0.0, min(1.0, float(fan_strength)))
        self.elapsed += delta_time
        new_sweeps = max(0, int(sweep_count) - self._last_sweep_count)
        self._last_sweep_count = int(sweep_count)
        direction_sign = 1 if direction == "right" else -1 if direction == "left" else 0
        active = strength >= config.INTERFERENCE_ACTIVE_STRENGTH
        drag = config.INTERFERENCE_DRAG_PER_30FPS_FRAME ** (delta_time * 30.0)

        for entity in self.entities:
            if entity.dispersed:
                continue
            if active:
                outward = entity.side * config.INTERFERENCE_OUTWARD_ACCELERATION * strength
                directional = direction_sign * config.INTERFERENCE_DIRECTION_BIAS * strength
                entity.velocity_x += (outward + directional) * delta_time
                if new_sweeps:
                    entity.velocity_x += (
                        entity.side
                        * config.INTERFERENCE_SWEEP_IMPULSE
                        * new_sweeps
                        * (0.35 + strength)
                    )
            entity.velocity_x *= drag
            entity.velocity_y *= drag
            entity.x += entity.velocity_x * delta_time
            entity.y += (
                entity.velocity_y
                + sin(self.elapsed * 1.8 + entity.phase) * config.INTERFERENCE_VERTICAL_WAVE_SPEED
            ) * delta_time
            entity.y = max(285.0, min(self.height - 45.0, entity.y))
            entity.dispersed = (
                entity.x < -config.INTERFERENCE_DISPERSED_MARGIN
                or entity.x > self.width + config.INTERFERENCE_DISPERSED_MARGIN
            )

    def render(self, canvas: np.ndarray) -> np.ndarray:
        """Draw real Latin and Cyrillic glyphs onto an OpenCV BGR canvas."""

        image = Image.fromarray(canvas[:, :, ::-1].copy())
        draw = ImageDraw.Draw(image)
        for entity in self.entities:
            if entity.dispersed:
                continue
            font = self._font(entity.size)
            bounds = draw.textbbox((0, 0), entity.glyph, font=font, stroke_width=1)
            width = bounds[2] - bounds[0]
            height = bounds[3] - bounds[1]
            position = (entity.x - width / 2, entity.y - height / 2 - bounds[1])
            draw.text(
                position,
                entity.glyph,
                font=font,
                fill=entity.color,
                stroke_width=1,
                stroke_fill=(18, 20, 28),
            )
        canvas[:] = np.asarray(image)[:, :, ::-1]
        return canvas

    def _font(self, size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
        if size not in self._font_cache:
            font_path = resolve_unicode_font()
            if font_path is not None:
                self._font_cache[size] = ImageFont.truetype(str(font_path), size)
            else:
                try:
                    self._font_cache[size] = ImageFont.truetype("DejaVuSans.ttf", size)
                except OSError:
                    self._font_cache[size] = ImageFont.load_default()
        return self._font_cache[size]


def resolve_unicode_font() -> Path | None:
    for candidate in config.UNICODE_FONT_CANDIDATES:
        path = Path(candidate)
        if path.exists():
            return path
    return None
