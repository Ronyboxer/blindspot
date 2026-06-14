from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from collections.abc import Callable
import time


class ButtonGesture(str, Enum):
    SINGLE = "single"
    DOUBLE = "double"
    LONG = "long"


@dataclass(frozen=True)
class ButtonTiming:
    double_click_window_s: float = 0.45
    long_press_s: float = 1.1


class ButtonInput:
    def wait_for_gesture(self, timing: ButtonTiming = ButtonTiming()) -> ButtonGesture:
        raise NotImplementedError

    def close(self) -> None:
        pass


class ConsoleButton(ButtonInput):
    def wait_for_gesture(self, timing: ButtonTiming = ButtonTiming()) -> ButtonGesture:
        raw = input("Gesture [s=single, d=double, l=long, Enter=single]: ").strip().lower()
        if raw in {"d", "double", "2"}:
            return ButtonGesture.DOUBLE
        if raw in {"l", "long", "hold"}:
            return ButtonGesture.LONG
        return ButtonGesture.SINGLE


class GpioButton(ButtonInput):
    def __init__(self, gpio_pin: int = 17, bounce_time_s: float = 0.08) -> None:
        try:
            from gpiozero import Button
        except ImportError as exc:
            raise RuntimeError("Install gpiozero on the Raspberry Pi to use GpioButton") from exc

        self._button = Button(gpio_pin, pull_up=True, bounce_time=bounce_time_s)

    def wait_for_gesture(self, timing: ButtonTiming = ButtonTiming()) -> ButtonGesture:
        first_duration = self._wait_for_press_duration()
        if first_duration >= timing.long_press_s:
            return ButtonGesture.LONG

        deadline = time.monotonic() + timing.double_click_window_s
        while time.monotonic() < deadline:
            if self._button.is_pressed:
                second_duration = self._wait_for_press_duration()
                if second_duration >= timing.long_press_s:
                    return ButtonGesture.LONG
                return ButtonGesture.DOUBLE
            time.sleep(0.01)

        return ButtonGesture.SINGLE

    def _wait_for_press_duration(self) -> float:
        self._button.wait_for_press()
        started = time.monotonic()
        time.sleep(0.05)
        self._button.wait_for_release()
        return time.monotonic() - started

    def close(self) -> None:
        self._button.close()


def run_gesture_loop(
    button: ButtonInput,
    on_gesture: Callable[[ButtonGesture], None],
    timing: ButtonTiming = ButtonTiming(),
) -> None:
    try:
        while True:
            gesture = button.wait_for_gesture(timing)
            on_gesture(gesture)
    finally:
        button.close()
