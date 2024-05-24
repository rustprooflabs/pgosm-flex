""" Unit tests to cover the import_mode module."""
import os
import unittest

import helpers


class ImportModeTests(unittest.TestCase):

    def test_import_mode_with_no_replication_or_update_returns_append_first_run_True(self):
        replication = False
        replication_update = False
        update = None

        expected = True
        input_mode = helpers.ImportMode(replication=replication,
                                        replication_update=replication_update,
                                        update=update,
                                        force=False)

        actual = input_mode.append_first_run
        self.assertEqual(expected, actual)

    def test_import_mode_with_replication_update_returns_append_first_run_False(self):
        replication = True
        replication_update = True
        update = None

        expected = False
        input_mode = helpers.ImportMode(replication=replication,
                                        replication_update=replication_update,
                                        update=update,
                                        force=False)

        actual = input_mode.append_first_run
        self.assertEqual(expected, actual)

    def test_import_mode_with_update_eq_create_returns_True(self):
        replication = True
        replication_update = True
        update = 'create'

        expected = True
        input_mode = helpers.ImportMode(replication=replication,
                                        replication_update=replication_update,
                                        update=update,
                                        force=False)

        actual = input_mode.append_first_run
        self.assertEqual(expected, actual)

    def test_import_mode_with_update_eq_append_returns_False(self):
        replication = True
        replication_update = True
        update = 'append'

        expected = False
        input_mode = helpers.ImportMode(replication=replication,
                                        replication_update=replication_update,
                                        update=update,
                                        force=False)

        actual = input_mode.append_first_run
        self.assertEqual(expected, actual)

    def test_import_mode_invalid_update_value_raises_ValueError(self):
        replication = False
        replication_update = False
        update = False # Boolean is invalid for this

        with self.assertRaises(ValueError):
            helpers.ImportMode(replication=replication,
                               replication_update=replication_update,
                               update=update,
                               force=False)



    def test_import_mode_with_update_create_sets_value_run_post_sql_True(self):
        replication = False
        replication_update = False
        update = 'create'
        expected = True
        input_mode = helpers.ImportMode(replication=replication,
                                        replication_update=replication_update,
                                        update=update,
                                        force=False)

        actual = input_mode.run_post_sql
        self.assertEqual(expected, actual)


    def test_import_mode_with_update_append_sets_value_run_post_sql_False(self):
        replication = False
        replication_update = False
        update = 'append'
        expected = False
        input_mode = helpers.ImportMode(replication=replication,
                                        replication_update=replication_update,
                                        update=update,
                                        force=False)

        actual = input_mode.run_post_sql
        self.assertEqual(expected, actual)

    def test_import_mode_okay_to_run_returns_expected_type(self):
        replication = False
        replication_update = False
        update = None
        force = True

        input_mode = helpers.ImportMode(replication=replication,
                                        replication_update=replication_update,
                                        update=update,
                                        force=force)

        expected = bool
        prior_import = {'replication': False}
        results = input_mode.okay_to_run(prior_import=prior_import)
        actual = type(results)
        self.assertEqual(expected, actual)


    def test_import_mode_okay_to_run_returns_true_when_force(self):
        replication = False
        replication_update = False
        update = None
        force = True

        input_mode = helpers.ImportMode(replication=replication,
                                        replication_update=replication_update,
                                        update=update,
                                        force=force)

        expected = True
        prior_import = {'replication': False}
        actual = input_mode.okay_to_run(prior_import=prior_import)
        self.assertEqual(expected, actual)


    def test_import_mode_okay_to_run_returns_false_when_prior_record_not_replication(self):
        """This tests the scenario when replication is True (e.g. --replication)
        but the DB returns a record saying the prior import did not use
        --replication. 

        This should return False to avoid overwriting data.
        """
        replication = True
        prior_import = {'replication': False,
                        'pgosm_flex_version_no_hash': '99.99.99'
                        }
        replication_update = False
        update = None
        force = False

        input_mode = helpers.ImportMode(replication=replication,
                                        replication_update=replication_update,
                                        update=update,
                                        force=force)

        expected = False

        actual = input_mode.okay_to_run(prior_import=prior_import)
        self.assertEqual(expected, actual)


    def test_import_mode_okay_to_run_returns_true_when_replication_prior_record_replication(self):
        """This tests the scenario when replication is True (e.g. --replication)
        and the DB returns a record saying the prior import used
        --replication. 

        This should return True to allow replication to updated
        """
        replication = True
        prior_import = {'replication': True,
                        'pgosm_flex_version_no_hash': '99.99.99'
                        }
        replication_update = False
        update = None
        force = False

        input_mode = helpers.ImportMode(replication=replication,
                                        replication_update=replication_update,
                                        update=update,
                                        force=force)

        expected = True

        actual = input_mode.okay_to_run(prior_import=prior_import)
        self.assertEqual(expected, actual)


    def test_import_mode_okay_to_run_returns_false_when_prior_import(self):
        """This tests the scenario when the DB returns a record saying a
        prior import exists.

        This should return False to protect the data.
        """
        replication = False
        prior_import = {'replication': False,
                        'pgosm_flex_version_no_hash': '99.99.99'
                        }
        replication_update = False
        update = None
        force = False

        input_mode = helpers.ImportMode(replication=replication,
                                        replication_update=replication_update,
                                        update=update,
                                        force=force)

        expected = False

        actual = input_mode.okay_to_run(prior_import=prior_import)
        self.assertEqual(expected, actual)

    def test_import_mode_okay_to_run_returns_true_no_prior_import(self):
        """This tests the scenario when the DB returns a record saying no
        prior import exists.

        This should return True.
        """
        replication = False
        prior_import = {}
        replication_update = False
        update = None
        force = False

        input_mode = helpers.ImportMode(replication=replication,
                                        replication_update=replication_update,
                                        update=update,
                                        force=force)

        expected = True

        actual = input_mode.okay_to_run(prior_import=prior_import)
        self.assertEqual(expected, actual)



    def test_import_mode_as_json_expected_type(self):
        replication = False
        replication_update = False
        update = None
        force = True

        input_mode = helpers.ImportMode(replication=replication,
                                        replication_update=replication_update,
                                        update=update,
                                        force=force)

        expected = str
        results = input_mode.as_json()
        actual = type(results)
        self.assertEqual(expected, actual)
