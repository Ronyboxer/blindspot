import unittest

from device.blindspot_device.imu import CrashDetector, IMUSample, ImpactDetector


class ImpactDetectorTests(unittest.TestCase):
    def test_impact_triggers_once_per_cooldown(self) -> None:
        detector = ImpactDetector(threshold_g=2.0, cooldown_s=2.0)

        self.assertTrue(detector.observe(IMUSample(0.0, 0, 0, 2.2, 0, 0)))
        self.assertFalse(detector.observe(IMUSample(1.0, 0, 0, 2.3, 0, 0)))
        self.assertTrue(detector.observe(IMUSample(2.2, 0, 0, 2.3, 0, 0)))


class CrashDetectorTests(unittest.TestCase):
    def test_crash_requires_impact_orientation_change_and_stillness(self) -> None:
        detector = CrashDetector(
            threshold_g=3.0,
            orientation_delta_deg=50.0,
            stillness_g=0.2,
            stillness_seconds=2.0,
        )

        samples = [
            IMUSample(0.0, 0, 0, 1.0, 0, 0),
            IMUSample(1.0, 0, 0, 3.2, 0, 0),
            IMUSample(2.0, 0, 0, 1.0, 80, 5),
            IMUSample(3.0, 0, 0, 1.0, 81, 5),
            IMUSample(4.1, 0, 0, 1.0, 82, 6),
        ]

        results = [detector.observe(sample) for sample in samples]

        self.assertEqual(results, [False, False, False, False, True])


if __name__ == "__main__":
    unittest.main()
