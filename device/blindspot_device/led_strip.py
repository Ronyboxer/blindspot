from __future__ import annotations

import time


class LedStrip:
    def ready(self) -> None:
        raise NotImplementedError

    def show_state(self, ride_active: bool = False, video_recording: bool = False) -> None:
        raise NotImplementedError

    def capturing(self) -> None:
        raise NotImplementedError

    def saved(self) -> None:
        raise NotImplementedError

    def error(self) -> None:
        raise NotImplementedError

    def off(self) -> None:
        raise NotImplementedError


class ConsoleLedStrip(LedStrip):
    def ready(self) -> None:
        print("[led] ready")

    def show_state(self, ride_active: bool = False, video_recording: bool = False) -> None:
        print(f"[led] state ride_active={ride_active} video_recording={video_recording}")

    def capturing(self) -> None:
        print("[led] capturing")

    def saved(self) -> None:
        print("[led] saved")

    def error(self) -> None:
        print("[led] error")

    def off(self) -> None:
        print("[led] off")


class NeoPixelStrip(LedStrip):
    def __init__(
        self,
        pixel_count: int = 8,
        gpio_name: str = "D18",
        brightness: float = 0.25,
    ) -> None:
        try:
            import board
            import neopixel
        except ImportError as exc:
            raise RuntimeError(
                "Install adafruit-circuitpython-neopixel on the Raspberry Pi to use NeoPixelStrip"
            ) from exc

        pin = getattr(board, gpio_name)
        self._pixels = neopixel.NeoPixel(
            pin,
            pixel_count,
            brightness=brightness,
            auto_write=False,
            pixel_order=neopixel.GRB,
        )
        self._count = pixel_count

    def ready(self) -> None:
        self.show_state()

    def show_state(self, ride_active: bool = False, video_recording: bool = False) -> None:
        if ride_active and video_recording:
            self._pattern([(120, 0, 0), (0, 70, 0)] * ((self._count + 1) // 2))
        elif video_recording:
            self._fill((120, 0, 0))
        elif ride_active:
            self._fill((0, 70, 0))
        else:
            self._pattern([(28, 22, 0)] + [(0, 0, 0)] * (self._count - 1))

    def capturing(self) -> None:
        self._fill((255, 160, 0))

    def saved(self) -> None:
        for _ in range(2):
            self._fill((0, 80, 0))
            time.sleep(0.12)
            self.off()
            time.sleep(0.08)

    def error(self) -> None:
        for _ in range(3):
            self._fill((120, 0, 0))
            time.sleep(0.12)
            self.off()
            time.sleep(0.08)

    def off(self) -> None:
        self._fill((0, 0, 0))

    def _fill(self, color: tuple[int, int, int]) -> None:
        for index in range(self._count):
            self._pixels[index] = color
        self._pixels.show()

    def _pattern(self, colors: list[tuple[int, int, int]]) -> None:
        for index in range(self._count):
            self._pixels[index] = colors[index % len(colors)]
        self._pixels.show()
