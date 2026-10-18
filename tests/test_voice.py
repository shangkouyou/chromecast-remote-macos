import time
import unittest

from gvtv_remote.voice import VoiceController


class FakeSink:
    def __init__(self):
        self.calls = []
        self.dry_run = True

    def fn_down(self):
        self.calls.append("down")

    def fn_up(self):
        self.calls.append("up")

    def fn_tap(self):
        self.calls.append("tap")


class FakeRunner:
    def __init__(self):
        self.actions = []

    def run(self, action):
        self.actions.append(action)


def wait_for(predicate, timeout=2.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(0.01)
    return False


class VoiceTest(unittest.TestCase):
    def make(self, **overrides):
        cfg = {
            "mode": "hold",
            "max_session_s": 30,
            "release_delay_ms": 0,
            "end_actions": [],
            "disconnect_bluetooth": False,
        }
        cfg.update(overrides)
        sink = FakeSink()
        runner = FakeRunner()
        voice = VoiceController(cfg, sink, runner, lambda _m: None)
        self.addCleanup(voice.close)
        return voice, sink, runner

    def test_hold(self):
        voice, sink, _ = self.make()
        voice.press()
        self.assertTrue(wait_for(lambda: sink.calls == ["down"]))
        voice.release()
        self.assertTrue(wait_for(lambda: sink.calls == ["down", "up"]))

    def test_toggle(self):
        voice, sink, _ = self.make(mode="toggle")
        voice.press()
        self.assertTrue(wait_for(lambda: sink.calls == ["tap"]))
        voice.press()
        self.assertTrue(wait_for(lambda: sink.calls == ["tap", "tap"]))

    def test_end_actions(self):
        voice, sink, runner = self.make(end_actions=["key:escape"])
        voice.press()
        voice.release()
        self.assertTrue(wait_for(lambda: len(runner.actions) == 1))
        self.assertEqual(runner.actions[0]["type"], "key")
        self.assertEqual(runner.actions[0]["chord"], "escape")

    def test_auto_stop(self):
        voice, sink, _ = self.make(mode="toggle", max_session_s=0.2)
        voice.press()
        self.assertTrue(wait_for(lambda: sink.calls == ["tap"]))
        self.assertTrue(wait_for(lambda: sink.calls == ["tap", "tap"], timeout=2.0))


if __name__ == "__main__":
    unittest.main()
