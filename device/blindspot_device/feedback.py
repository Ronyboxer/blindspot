class Feedback:
    def flag_saved(self) -> None:
        raise NotImplementedError

    def crash_countdown(self) -> None:
        raise NotImplementedError

    def synced(self) -> None:
        raise NotImplementedError


class ConsoleFeedback(Feedback):
    def flag_saved(self) -> None:
        print("[feedback] flag saved")

    def crash_countdown(self) -> None:
        print("[feedback] crash countdown")

    def synced(self) -> None:
        print("[feedback] synced")
