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


@dataclass(frozen=True)
class PalmPhysicsInput:
    x: float
    y: float
    velocity_x: float
    velocity_y: float
    previous_x: float | None = None
    previous_y: float | None = None
    stroke_phase: str = "active"
    stroke_direction: int = 0
    stroke_id: int = 1
    auto_dispersion: bool = False


class PalmMotionTracker:
    """Convert palm positions into velocity with brief classification grace."""

    def __init__(self) -> None:
        self._last_x: float | None = None
        self._last_y: float | None = None
        self._last_time: float | None = None
        self._last_open_palm_at: float | None = None
        self._neutral_armed = False
        self._active_direction = 0
        self._stroke_id = 0
        self.stroke_phase = "waiting"
        self.stroke_direction = 0
        self.velocity_x = 0.0
        self.velocity_y = 0.0

    def update(
        self,
        x: float | None,
        y: float | None,
        now: float,
        open_palm: bool,
    ) -> PalmPhysicsInput | None:
        now = float(now)
        if x is None or y is None:
            self.clear_tracking()
            return None
        if open_palm:
            self._last_open_palm_at = now
        elif (
            self._last_open_palm_at is None
            or now - self._last_open_palm_at > config.PHYSICS_OPEN_PALM_GRACE_TIME
        ):
            self.clear_tracking()
            return None
        x = float(x)
        y = float(y)
        previous_x = self._last_x
        previous_y = self._last_y
        if self._last_x is not None and self._last_y is not None and self._last_time is not None:
            delta_time = max(1e-6, now - self._last_time)
            raw_velocity_x = _clamp(
                (x - self._last_x) / delta_time,
                -config.PALM_VELOCITY_MAX,
                config.PALM_VELOCITY_MAX,
            )
            raw_velocity_y = _clamp(
                (y - self._last_y) / delta_time,
                -config.PALM_VELOCITY_MAX,
                config.PALM_VELOCITY_MAX,
            )
            factor = config.PALM_VELOCITY_SMOOTHING
            self.velocity_x += factor * (raw_velocity_x - self.velocity_x)
            self.velocity_y += factor * (raw_velocity_y - self.velocity_y)
        else:
            self.velocity_x = 0.0
            self.velocity_y = 0.0
        self._last_x = x
        self._last_y = y
        self._last_time = now
        (
            self.stroke_phase,
            self.stroke_direction,
            active_previous_x,
            active_previous_y,
        ) = self._classify_stroke(
            x,
            y,
            x if previous_x is None else previous_x,
            y if previous_y is None else previous_y,
        )
        return PalmPhysicsInput(
            x,
            y,
            self.velocity_x,
            self.velocity_y,
            active_previous_x,
            active_previous_y,
            self.stroke_phase,
            self.stroke_direction,
            self._stroke_id,
        )

    def _classify_stroke(
        self,
        x: float,
        y: float,
        previous_x: float,
        previous_y: float,
    ) -> tuple[str, int, float, float]:
        center = config.INTERFERENCE_CENTER_X
        left_boundary = center - config.HAND_NEUTRAL_HALF_WIDTH
        right_boundary = center + config.HAND_NEUTRAL_HALF_WIDTH
        if left_boundary <= x <= right_boundary:
            self._neutral_armed = True
            self._active_direction = 0
            return "ready", 0, x, y

        side = -1 if x < left_boundary else 1
        velocity_direction = _sign(self.velocity_x)
        moving_outward = (
            velocity_direction == side
            and abs(self.velocity_x) >= config.HAND_ACTIVE_STROKE_MIN_VELOCITY
        )
        crossed_neutral = (
            side < 0 and previous_x >= left_boundary
            or side > 0 and previous_x <= right_boundary
        )
        if moving_outward and (
            self._active_direction == side
            or self._neutral_armed
            or crossed_neutral
        ):
            if self._active_direction != side:
                self._stroke_id += 1
            self._active_direction = side
            self._neutral_armed = False
            clipped_x, clipped_y = _clip_segment_to_outward_boundary(
                previous_x,
                previous_y,
                x,
                y,
                left_boundary if side < 0 else right_boundary,
                side,
            )
            return "active", side, clipped_x, clipped_y

        if velocity_direction != self._active_direction:
            self._active_direction = 0
        return "recovery", side, x, y

    def clear_tracking(self) -> None:
        self._last_x = None
        self._last_y = None
        self._last_time = None
        self._last_open_palm_at = None
        self._neutral_armed = False
        self._active_direction = 0
        self.stroke_phase = "waiting"
        self.stroke_direction = 0
        self.velocity_x = 0.0
        self.velocity_y = 0.0

    def reset(self) -> None:
        self.clear_tracking()
        self._stroke_id = 0


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
    side: int = 1


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
        self.elapsed = 0.0
        self.hand_force_active = False
        self.letters_inside_influence_radius = 0
        self.last_impulse_strength = 0.0
        self.last_impulse_stroke_id = 0
        self.stroke_phase = "waiting"
        self.stroke_direction = 0
        self.auto_dispersion_strength = 0.0
        self._font_cache: dict[int, ImageFont.FreeTypeFont | ImageFont.ImageFont] = {}
        self._glyph_cache: dict[
            tuple[str, int, tuple[int, int, int]],
            tuple[np.ndarray, np.ndarray],
        ] = {}
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
            side = -1 if x < config.INTERFERENCE_CENTER_X else 1
            if x == config.INTERFERENCE_CENTER_X:
                side = -1 if index % 2 else 1
            self.entities.append(LetterEntity(
                glyph=glyph,
                x=x,
                y=y,
                mass=random.uniform(config.LETTER_MASS_MIN, config.LETTER_MASS_MAX),
                radius=size * config.LETTER_RADIUS_SCALE,
                size=size,
                color=random.choice(self._colors),
                side=side,
            ))
        self.elapsed = 0.0
        self.hand_force_active = False
        self.letters_inside_influence_radius = 0
        self.last_impulse_strength = 0.0
        self.last_impulse_stroke_id = 0
        self.stroke_phase = "waiting"
        self.stroke_direction = 0
        self.auto_dispersion_strength = 0.0

    def update(self, delta_time: float, palm: PalmPhysicsInput | None = None) -> None:
        delta_time = max(0.0, min(config.LETTER_PHYSICS_MAX_DT, float(delta_time)))
        self.elapsed += delta_time
        drag = exp(-config.LETTER_AIR_DRAG * delta_time)
        self.stroke_phase = "waiting" if palm is None else palm.stroke_phase
        self.stroke_direction = 0 if palm is None else palm.stroke_direction
        active_palm = palm is not None and palm.stroke_phase == "active"
        influence = self._influence_falloffs(palm) if active_palm else {}
        self.letters_inside_influence_radius = len(influence)
        palm_speed = 0.0 if palm is None else abs(palm.velocity_x) + abs(palm.velocity_y)
        self.hand_force_active = active_palm and bool(influence) and palm_speed >= config.HAND_MIN_FORCE_VELOCITY
        motion_strength = self._auto_dispersion_motion_strength(palm)
        self.auto_dispersion_strength = max(
            motion_strength,
            self.auto_dispersion_strength * exp(-config.AUTO_DISPERSION_DECAY * delta_time),
        )
        impulse_strength_ratio = self._impulse_strength_ratio(palm, bool(influence))
        applied_impulse_strength = 0.0

        for entity in self.entities:
            if entity.dispersed:
                continue
            entity.acceleration_x = 0.0
            entity.acceleration_y = config.LETTER_GRAVITY
            if self.auto_dispersion_strength > 0.0:
                self.apply_force(
                    entity,
                    entity.side * config.AUTO_DISPERSION_ACCELERATION * self.auto_dispersion_strength,
                    0.0,
                )
            falloff = influence.get(id(entity), 0.0)
            if palm is not None and falloff > 0.0:
                force_x = palm.velocity_x * config.HAND_HORIZONTAL_FORCE_GAIN * falloff
                force_y = palm.velocity_y * config.HAND_VERTICAL_FORCE_GAIN * falloff
                self.apply_force(entity, force_x, force_y)
                if impulse_strength_ratio > 0.0:
                    impulse_x = (
                        palm.velocity_x
                        * config.HAND_IMPULSE_GAIN
                        * impulse_strength_ratio
                        * falloff
                    )
                    entity.velocity_x += impulse_x / entity.mass
                    entity.velocity_y -= abs(impulse_x) * config.HAND_IMPULSE_LIFT_RATIO / entity.mass
                    applied_impulse_strength = max(applied_impulse_strength, abs(impulse_x))
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
        if applied_impulse_strength > 0.0:
            self.last_impulse_strength = applied_impulse_strength

    @staticmethod
    def _auto_dispersion_motion_strength(palm: PalmPhysicsInput | None) -> float:
        if palm is None or not palm.auto_dispersion or palm.stroke_phase != "active":
            return 0.0
        span = max(
            1e-6,
            config.AUTO_DISPERSION_SPEED_REFERENCE - config.AUTO_DISPERSION_MOTION_THRESHOLD,
        )
        return _clamp(
            (abs(palm.velocity_x) - config.AUTO_DISPERSION_MOTION_THRESHOLD) / span,
            0.0,
            1.0,
        )

    def _influence_falloffs(self, palm: PalmPhysicsInput | None) -> dict[int, float]:
        if palm is None:
            return {}
        falloffs: dict[int, float] = {}
        radius = config.HAND_FORCE_RADIUS
        for entity in self.entities:
            if entity.dispersed:
                continue
            previous_x = palm.x if palm.previous_x is None else palm.previous_x
            previous_y = palm.y if palm.previous_y is None else palm.previous_y
            center_distance = _distance_to_segment(
                entity.x,
                entity.y,
                previous_x,
                previous_y,
                palm.x,
                palm.y,
            )
            surface_distance = max(0.0, center_distance - entity.radius)
            if surface_distance <= radius:
                linear = 1.0 - surface_distance / radius
                falloffs[id(entity)] = linear ** config.HAND_FORCE_FALLOFF_EXPONENT
        return falloffs

    def _impulse_strength_ratio(self, palm: PalmPhysicsInput | None, letters_in_range: bool) -> float:
        if (
            palm is None
            or palm.stroke_phase != "active"
            or not letters_in_range
            or palm.stroke_id <= self.last_impulse_stroke_id
        ):
            return 0.0
        speed_x = abs(palm.velocity_x)
        if speed_x < config.HAND_IMPULSE_MIN_VELOCITY:
            return 0.0
        velocity_range = max(
            1e-6,
            config.HAND_IMPULSE_FULL_VELOCITY - config.HAND_IMPULSE_MIN_VELOCITY,
        )
        progress = _clamp(
            (speed_x - config.HAND_IMPULSE_MIN_VELOCITY) / velocity_range,
            0.0,
            1.0,
        )
        smooth_progress = progress * progress * (3.0 - 2.0 * progress)
        self.last_impulse_stroke_id = palm.stroke_id
        return (
            config.HAND_IMPULSE_MIN_STRENGTH_RATIO
            + (1.0 - config.HAND_IMPULSE_MIN_STRENGTH_RATIO) * smooth_progress
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
        """Blend cached Unicode glyph sprites directly onto a BGR canvas."""

        for entity in self.entities:
            if entity.dispersed:
                continue
            premultiplied, inverse_alpha = self._glyph_sprite(entity)
            self._blend_sprite(canvas, premultiplied, inverse_alpha, entity.x, entity.y)
        return canvas

    def _glyph_sprite(self, entity: LetterEntity) -> tuple[np.ndarray, np.ndarray]:
        key = (entity.glyph, entity.size, entity.color)
        cached = self._glyph_cache.get(key)
        if cached is not None:
            return cached
        font = self._font(entity.size)
        measuring_image = Image.new("RGBA", (1, 1), (0, 0, 0, 0))
        measuring_draw = ImageDraw.Draw(measuring_image)
        bounds = measuring_draw.textbbox((0, 0), entity.glyph, font=font, stroke_width=1)
        width = max(1, bounds[2] - bounds[0])
        height = max(1, bounds[3] - bounds[1])
        image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)
        draw.text(
            (-bounds[0], -bounds[1]),
            entity.glyph,
            font=font,
            fill=(*entity.color, 255),
            stroke_width=1,
            stroke_fill=(18, 20, 28, 255),
        )
        rgba = np.asarray(image, dtype=np.uint8)
        alpha = rgba[:, :, 3:4].astype(np.float32) / 255.0
        bgr = rgba[:, :, :3][:, :, ::-1].astype(np.float32)
        cached = (bgr * alpha, 1.0 - alpha)
        self._glyph_cache[key] = cached
        return cached

    @staticmethod
    def _blend_sprite(
        canvas: np.ndarray,
        premultiplied: np.ndarray,
        inverse_alpha: np.ndarray,
        center_x: float,
        center_y: float,
    ) -> None:
        sprite_height, sprite_width = premultiplied.shape[:2]
        left = int(round(center_x - sprite_width / 2))
        top = int(round(center_y - sprite_height / 2))
        right = left + sprite_width
        bottom = top + sprite_height
        canvas_height, canvas_width = canvas.shape[:2]
        clipped_left = max(0, left)
        clipped_top = max(0, top)
        clipped_right = min(canvas_width, right)
        clipped_bottom = min(canvas_height, bottom)
        if clipped_left >= clipped_right or clipped_top >= clipped_bottom:
            return
        source_left = clipped_left - left
        source_top = clipped_top - top
        source_right = source_left + clipped_right - clipped_left
        source_bottom = source_top + clipped_bottom - clipped_top
        source = premultiplied[source_top:source_bottom, source_left:source_right]
        inverse = inverse_alpha[source_top:source_bottom, source_left:source_right]
        destination = canvas[clipped_top:clipped_bottom, clipped_left:clipped_right]
        destination[:] = (source + destination * inverse).astype(np.uint8)

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


def _clamp(value: float, minimum: float, maximum: float) -> float:
    return max(minimum, min(maximum, value))


def _sign(value: float) -> int:
    return 1 if value > 0.0 else -1 if value < 0.0 else 0


def _clip_segment_to_outward_boundary(
    start_x: float,
    start_y: float,
    end_x: float,
    end_y: float,
    boundary_x: float,
    direction: int,
) -> tuple[float, float]:
    already_outside = start_x <= boundary_x if direction < 0 else start_x >= boundary_x
    if already_outside or abs(end_x - start_x) <= 1e-9:
        return start_x, start_y
    ratio = _clamp((boundary_x - start_x) / (end_x - start_x), 0.0, 1.0)
    return boundary_x, start_y + ratio * (end_y - start_y)


def _distance_to_segment(
    point_x: float,
    point_y: float,
    start_x: float,
    start_y: float,
    end_x: float,
    end_y: float,
) -> float:
    """Shortest distance from a letter center to the palm's swept path."""

    delta_x = end_x - start_x
    delta_y = end_y - start_y
    length_squared = delta_x * delta_x + delta_y * delta_y
    if length_squared <= 1e-9:
        return ((point_x - end_x) ** 2 + (point_y - end_y) ** 2) ** 0.5
    projection = (
        (point_x - start_x) * delta_x
        + (point_y - start_y) * delta_y
    ) / length_squared
    projection = _clamp(projection, 0.0, 1.0)
    nearest_x = start_x + projection * delta_x
    nearest_y = start_y + projection * delta_y
    return ((point_x - nearest_x) ** 2 + (point_y - nearest_y) ** 2) ** 0.5
