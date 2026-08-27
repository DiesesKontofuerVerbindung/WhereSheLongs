"""Unicode letter entities that visualize mixed voices being fanned apart."""

from __future__ import annotations

from dataclasses import dataclass
from math import exp
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
    mass: float
    radius: float
    size: int
    color: tuple[int, int, int]
    velocity_x: float = 0.0
    velocity_y: float = 0.0
    acceleration_x: float = 0.0
    acceleration_y: float = 0.0
    dispersed: bool = False


class InterferenceField:
    """Maintain deterministic Unicode letter entities with force state."""

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
        self._font_cache: dict[int, ImageFont.FreeTypeFont | ImageFont.ImageFont] = {}
        self.reset()

    @property
    def dispersed_count(self) -> int:
        return sum(entity.dispersed for entity in self.entities)

    @property
    def dispersed_ratio(self) -> float:
        return 0.0 if not self.entities else self.dispersed_count / len(self.entities)

    @property
    def mean_velocity_x(self) -> float:
        active = [entity.velocity_x for entity in self.entities if not entity.dispersed]
        return 0.0 if not active else sum(active) / len(active)

    @property
    def mean_velocity_y(self) -> float:
        active = [entity.velocity_y for entity in self.entities if not entity.dispersed]
        return 0.0 if not active else sum(active) / len(active)

    def reset(self) -> None:
        random = Random(self.seed)
        glyphs = list(LATIN_GLYPHS + CYRILLIC_GLYPHS)
        random.shuffle(glyphs)
        self.entities = []
        for index in range(config.INTERFERENCE_ENTITY_COUNT):
            glyph = glyphs[index % len(glyphs)]
            size = random.randint(config.INTERFERENCE_MIN_FONT_SIZE, config.INTERFERENCE_MAX_FONT_SIZE)
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
                mass=random.uniform(config.LETTER_MASS_MIN, config.LETTER_MASS_MAX),
                radius=size * config.LETTER_RADIUS_SCALE,
                size=size,
                color=random.choice(self._colors),
            ))

    def update(self, delta_time: float) -> None:
        delta_time = max(0.0, min(config.LETTER_PHYSICS_MAX_DT, float(delta_time)))
        drag = exp(-config.LETTER_AIR_DRAG * delta_time)
        for entity in self.entities:
            if entity.dispersed:
                continue
            entity.acceleration_x = 0.0
            entity.acceleration_y = config.LETTER_GRAVITY
            entity.velocity_x += entity.acceleration_x * delta_time
            entity.velocity_y += entity.acceleration_y * delta_time
            entity.velocity_x *= drag
            entity.velocity_y *= drag
            entity.x += entity.velocity_x * delta_time
            entity.y += entity.velocity_y * delta_time
            self._resolve_floor_collision(entity, delta_time)
            entity.dispersed = (
                entity.x < -config.INTERFERENCE_DISPERSED_MARGIN
                or entity.x > self.width + config.INTERFERENCE_DISPERSED_MARGIN
            )

    @staticmethod
    def apply_force(entity: LetterEntity, force_x: float, force_y: float) -> None:
        entity.acceleration_x += force_x / entity.mass
        entity.acceleration_y += force_y / entity.mass

    @staticmethod
    def _resolve_floor_collision(entity: LetterEntity, delta_time: float) -> None:
        floor_center_y = config.LETTER_FLOOR_Y - entity.radius
        if entity.y < floor_center_y:
            return
        entity.y = floor_center_y
        if entity.velocity_y > 0.0:
            if entity.velocity_y < config.LETTER_SETTLE_VERTICAL_SPEED:
                entity.velocity_y = 0.0
            else:
                entity.velocity_y = -entity.velocity_y * config.LETTER_RESTITUTION
        entity.velocity_x *= exp(-config.LETTER_FLOOR_FRICTION * delta_time)

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
