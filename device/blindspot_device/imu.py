from __future__ import annotations

from dataclasses import dataclass
import math


@dataclass(frozen=True)
class IMUSample:
    timestamp_s: float
    ax_g: float
    ay_g: float
    az_g: float
    pitch_deg: float
    roll_deg: float

    @property
    def magnitude_g(self) -> float:
        return math.sqrt(self.ax_g**2 + self.ay_g**2 + self.az_g**2)


class ImpactDetector:
    def __init__(self, threshold_g: float = 2.4, cooldown_s: float = 2.0) -> None:
        self.threshold_g = threshold_g
        self.cooldown_s = cooldown_s
        self._last_impact_s = -float("inf")

    def observe(self, sample: IMUSample) -> bool:
        if sample.magnitude_g < self.threshold_g:
            return False
        if sample.timestamp_s - self._last_impact_s < self.cooldown_s:
            return False
        self._last_impact_s = sample.timestamp_s
        return True


class CrashDetector:
    """Rule-based v1 crash detector: impact, orientation change, then stillness."""

    def __init__(
        self,
        threshold_g: float = 3.0,
        orientation_delta_deg: float = 55.0,
        stillness_g: float = 0.18,
        stillness_seconds: float = 3.0,
    ) -> None:
        self.threshold_g = threshold_g
        self.orientation_delta_deg = orientation_delta_deg
        self.stillness_g = stillness_g
        self.stillness_seconds = stillness_seconds
        self._pre_impact_orientation: tuple[float, float] | None = None
        self._candidate_started_s: float | None = None
        self._still_started_s: float | None = None

    def observe(self, sample: IMUSample) -> bool:
        if self._pre_impact_orientation is None:
            self._pre_impact_orientation = (sample.pitch_deg, sample.roll_deg)

        if self._candidate_started_s is None:
            if sample.magnitude_g >= self.threshold_g:
                self._candidate_started_s = sample.timestamp_s
            else:
                self._pre_impact_orientation = (sample.pitch_deg, sample.roll_deg)
            return False

        orientation_changed = self._orientation_changed(sample)
        still = abs(sample.magnitude_g - 1.0) <= self.stillness_g

        if not orientation_changed:
            if sample.timestamp_s - self._candidate_started_s > 5:
                self.reset(sample)
            return False

        if still:
            if self._still_started_s is None:
                self._still_started_s = sample.timestamp_s
            if sample.timestamp_s - self._still_started_s >= self.stillness_seconds:
                self.reset(sample)
                return True
        else:
            self._still_started_s = None

        return False

    def reset(self, sample: IMUSample) -> None:
        self._pre_impact_orientation = (sample.pitch_deg, sample.roll_deg)
        self._candidate_started_s = None
        self._still_started_s = None

    def _orientation_changed(self, sample: IMUSample) -> bool:
        assert self._pre_impact_orientation is not None
        start_pitch, start_roll = self._pre_impact_orientation
        delta = math.hypot(sample.pitch_deg - start_pitch, sample.roll_deg - start_roll)
        return delta >= self.orientation_delta_deg
