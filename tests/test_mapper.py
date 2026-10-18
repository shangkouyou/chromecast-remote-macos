import unittest

from gvtv_remote.descriptor import parse
from gvtv_remote.mapper import Mapper, canonical_id

DESC = bytes.fromhex(
    "050c0901a10185010a9e0109cd0942094309440945094109e2"
    "0a21020a23020a240209e909ea0977097809790989150125"
    "11950275088100c0"
)


class FakeRunner:
    def __init__(self):
        self.actions = []

    def run(self, action):
        self.actions.append(action)


class FakeVoice:
    def __init__(self):
        self.events = []

    def press(self):
        self.events.append("press")

    def release(self):
        self.events.append("release")


def make_mapper(mapping=None, voice_button="assistant"):
    cfg = {
        "mapping": mapping
        or {
            "c:0x42": "key:space",
            "c:0x41": "key:return",
            "c:0x221": "voice",
            "c:0x223": {"type": "shell", "value": "true"},
        },
        "voice": {"button": voice_button},
    }
    runner = FakeRunner()
    voice = FakeVoice()
    mapper = Mapper(cfg, parse(DESC), runner, voice, lambda _m: None)
    return mapper, runner, voice


class MapperTest(unittest.TestCase):
    def test_press_and_release(self):
        mapper, runner, voice = make_mapper()
        mapper.handle_report(1, bytes([3, 0]))
        self.assertEqual(len(runner.actions), 1)
        self.assertEqual(runner.actions[0]["type"], "key")
        # 按住不放（重复上报相同状态）不重复触发
        mapper.handle_report(1, bytes([3, 0]))
        self.assertEqual(len(runner.actions), 1)
        mapper.handle_report(1, bytes([0, 0]))
        self.assertEqual(len(runner.actions), 1)

    def test_two_buttons(self):
        mapper, runner, _ = make_mapper()
        mapper.handle_report(1, bytes([3, 7]))
        self.assertEqual(len(runner.actions), 2)
        mapper.handle_report(1, bytes([0, 0]))
        self.assertEqual(len(runner.actions), 2)

    def test_voice_button(self):
        mapper, runner, voice = make_mapper()
        mapper.handle_report(1, bytes([9, 0]))
        self.assertEqual(voice.events, ["press"])
        mapper.handle_report(1, bytes([0, 0]))
        self.assertEqual(voice.events, ["press", "release"])

    def test_unknown_button(self):
        mapper, runner, voice = make_mapper()
        mapper.handle_report(1, bytes([17, 0]))  # 0x89 未绑定
        self.assertEqual(runner.actions, [])
        self.assertEqual(voice.events, [])

    def test_learning(self):
        mapper, runner, voice = make_mapper()
        seen = []
        mapper.learning = True
        mapper.learn_callback = lambda bid, label: seen.append((bid, label))
        mapper.handle_report(1, bytes([9, 0]))
        self.assertEqual(seen[0][0], "c:0x221")
        self.assertEqual(runner.actions, [])

    def test_canonical_ids(self):
        self.assertEqual(canonical_id("assistant"), "c:0x221")
        self.assertEqual(canonical_id("c:0x42"), "c:0x42")
        self.assertEqual(canonical_id("C:0X42"), "c:0x42")
        with self.assertRaises(ValueError):
            canonical_id("nope")


if __name__ == "__main__":
    unittest.main()
