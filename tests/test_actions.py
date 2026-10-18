import unittest

from gvtv_remote.actions import ActionError, describe_action, parse_action
from gvtv_remote.events import KEYCODES, MEDIA_KEYS, parse_chord


class ActionTest(unittest.TestCase):
    def test_key_chord(self):
        action = parse_action("key:cmd+shift+4")
        self.assertEqual(action["type"], "key")
        self.assertEqual(action["chord"], "cmd+shift+4")

    def test_key_hold_option(self):
        action = parse_action("key:f5,hold=80")
        self.assertEqual(action["hold_ms"], 80)

    def test_media(self):
        self.assertEqual(parse_action("media:play_pause")["name"], "play_pause")

    def test_app_url_shell_text(self):
        self.assertEqual(parse_action("app:Safari")["value"], "Safari")
        self.assertEqual(parse_action("url:https://example.com")["value"], "https://example.com")
        self.assertEqual(parse_action("shell:say hi")["value"], "say hi")
        self.assertEqual(parse_action("text:你好")["value"], "你好")

    def test_voice_and_none(self):
        self.assertEqual(parse_action("voice")["type"], "voice")
        self.assertEqual(parse_action("none")["type"], "none")

    def test_structured(self):
        action = parse_action({"type": "key", "key": "space", "modifiers": ["cmd"]})
        self.assertEqual(action["type"], "key")
        self.assertIn("space", describe_action(action))

    def test_invalid(self):
        with self.assertRaises(ActionError):
            parse_action("key:notakey")
        with self.assertRaises(ActionError):
            parse_action("media:nope")
        with self.assertRaises(ActionError):
            parse_action("bogus:1")

    def test_parse_chord(self):
        code, mods = parse_chord("cmd+c")
        self.assertEqual(code, KEYCODES["c"])
        self.assertEqual(len(mods), 1)
        with self.assertRaises(ValueError):
            parse_chord("hyper+c")

    def test_media_keys_exist(self):
        for name in ("volume_up", "volume_down", "mute", "play_pause"):
            self.assertIn(name, MEDIA_KEYS)


if __name__ == "__main__":
    unittest.main()
