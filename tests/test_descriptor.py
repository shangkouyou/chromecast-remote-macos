import unittest

from gvtv_remote.descriptor import decode, parse, usage_id, usage_name

CHROMECAST = bytes.fromhex(
    "050c0901a10185010a9e0109cd0942094309440945094109e2"
    "0a21020a23020a240209e909ea0977097809790989150125"
    "11950275088100c0"
)

BOOT_KEYBOARD = bytes.fromhex(
    "05010906a101050719e029e715002501750195088102950175088101"
    "95057501050819012905910295017503910195067508150025650507"
    "190029658100c0"
)


class DescriptorTest(unittest.TestCase):
    def test_chromecast_fields(self):
        fields = parse(CHROMECAST)
        self.assertIn(1, fields)
        item = fields[1][0]
        self.assertEqual(item.report_count, 2)
        self.assertEqual(item.report_size, 8)
        self.assertEqual(len(item.usages), 17)
        self.assertEqual(item.usages[0], 0x19E)
        self.assertEqual(item.usages[8], 0x221)
        self.assertEqual(item.usages[16], 0x89)

    def test_chromecast_values(self):
        fields = parse(CHROMECAST)
        self.assertEqual(decode(fields, 1, bytes([9, 0])), [(0x0C, 0x221)])
        self.assertEqual(decode(fields, 1, bytes([3, 0])), [(0x0C, 0x42)])
        self.assertEqual(
            decode(fields, 1, bytes([3, 4])), [(0x0C, 0x42), (0x0C, 0x43)]
        )
        self.assertEqual(decode(fields, 1, bytes([0, 0])), [])

    def test_names(self):
        self.assertEqual(usage_id(0x0C, 0x221), "c:0x221")
        self.assertIn("Assistant", usage_name(0x0C, 0x221))

    def test_boot_keyboard(self):
        fields = parse(BOOT_KEYBOARD)
        # 修饰键字节 + 6 个按键槽位
        self.assertTrue(fields[0])
        self.assertEqual(decode(fields, 0, bytes([0, 0, 0x04, 0, 0, 0, 0, 0])), [(0x07, 0x04)])


if __name__ == "__main__":
    unittest.main()
