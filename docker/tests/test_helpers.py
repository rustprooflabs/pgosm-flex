""" Unit tests to cover the DB module."""
import os
import unittest

import pgosm_flex, helpers

pgosm_flex.setup_logger(debug=True)


class HelpersTests(unittest.TestCase):

    def test_get_today_returns_str(self):
        expected = str
        actual = type(helpers.get_today())
        self.assertEqual(expected, actual)

    def test_verify_checksum_returns_None_when_valid_md5(self):
        txt_file = 'checksum-test.txt'
        md5_file = f'{txt_file}.md5'

        path = os.getcwd()
        txt_content = 'this is a test'
        md5_content = f'54b0c58c7ce9f2a8b551351102ee0938  {txt_file}'

        with open(txt_file, "w") as f:
            f.write(txt_content)

        with open(md5_file, "w") as f:
            f.write(md5_content)

        expected = None
        actual = helpers.verify_checksum(md5_file=md5_file, path=path)
        self.assertEqual(expected, actual)

    def test_verify_checksum_raises_SystemExit_invalid_md5(self):
        txt_file = 'checksum-test.txt'
        md5_file = f'{txt_file}.md5'

        path = os.getcwd()
        txt_content = 'data has been changed oh no'
        md5_content = f'54b0c58c7ce9f2a8b551351102ee0938  {txt_file}'

        with open(txt_file, "w") as f:
            f.write(txt_content)

        with open(md5_file, "w") as f:
            f.write(md5_content)

        with self.assertRaises(SystemExit):
            helpers.verify_checksum(md5_file=md5_file, path=path)

