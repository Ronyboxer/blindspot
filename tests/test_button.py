import unittest

from device.blindspot_device.button import ButtonGesture, ConsoleButton


class ConsoleButtonTests(unittest.TestCase):
    def test_console_mapping(self) -> None:
        # The real console path is interactive; this test protects the public enum values
        # that are used in saved photo prefixes and downstream scripts.
        self.assertEqual(ButtonGesture.SINGLE.value, "single")
        self.assertEqual(ButtonGesture.DOUBLE.value, "double")
        self.assertEqual(ButtonGesture.LONG.value, "long")
        self.assertIsInstance(ConsoleButton(), ConsoleButton)


if __name__ == "__main__":
    unittest.main()
