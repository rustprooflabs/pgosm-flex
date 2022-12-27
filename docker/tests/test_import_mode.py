""" Unit tests to cover the import_mode module."""
import os
import unittest

import import_mode


class ImportModeTests(unittest.TestCase):

    def test_import_mode_with_no_replication_or_update_returns_append_first_run_True(self):
        replication = False
        replication_update = False
        update = None

        expected = True
        im = import_mode.ImportMode(replication=replication,
                                    replication_update=replication_update,
                                    update=update)

        actual = im.append_first_run
        self.assertEqual(expected, actual)

    def test_import_mode_with_replication_update_returns_append_first_run_False(self):
        replication = True
        replication_update = True
        update = None

        expected = False
        im = import_mode.ImportMode(replication=replication,
                                    replication_update=replication_update,
                                    update=update)

        actual = im.append_first_run
        self.assertEqual(expected, actual)

    def test_import_mode_with_update_eq_create_returns_True(self):
        replication = True
        replication_update = True
        update = 'create'

        expected = True
        im = import_mode.ImportMode(replication=replication,
                                    replication_update=replication_update,
                                    update=update)

        actual = im.append_first_run
        self.assertEqual(expected, actual)

    def test_import_mode_with_update_eq_append_returns_False(self):
        replication = True
        replication_update = True
        update = 'append'

        expected = False
        im = import_mode.ImportMode(replication=replication,
                                    replication_update=replication_update,
                                    update=update)

        actual = im.append_first_run
        self.assertEqual(expected, actual)

    def test_import_mode_invalid_update_value_raises_ValueError(self):
        replication = False
        replication_update = False
        update = False # Boolean is invalid for this

        with self.assertRaises(ValueError):
            import_mode.ImportMode(replication=replication,
                                   replication_update=replication_update,
                                   update=update)


