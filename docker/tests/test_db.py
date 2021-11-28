""" Unit tests to cover the DB module."""
import os
import unittest
from unittest import mock

import db

POSTGRES_USER = 'my_pg_user'
POSTGRES_PASSWORD = 'here_for_fun'

PG_USER_ONLY = {'POSTGRES_USER': POSTGRES_USER,
                'POSTGRES_PASSWORD': ''}
PG_USER_AND_PW = {'POSTGRES_USER': POSTGRES_USER,
                  'POSTGRES_PASSWORD': POSTGRES_PASSWORD}


class DBTests(unittest.TestCase):

    @mock.patch.dict(os.environ, PG_USER_ONLY)
    def test_get_pg_user_pass_user_only_returns_expected_values(self):
        expected_user = POSTGRES_USER
        expected_pw = None
        results = db.get_pg_user_pass()
        self.assertEqual(expected_user, results['pg_user'])
        self.assertEqual(expected_pw, results['pg_pass'])


    @mock.patch.dict(os.environ, PG_USER_AND_PW)
    def test_get_pg_user_pass_user_w_pw_returns_expected_values(self):
        expected_user = POSTGRES_USER
        expected_pw = POSTGRES_PASSWORD
        results = db.get_pg_user_pass()
        self.assertEqual(expected_user, results['pg_user'])
        self.assertEqual(expected_pw, results['pg_pass'])


    @mock.patch.dict(os.environ, PG_USER_ONLY)
    def test_connection_string_user_only_returns_expected_string(self):
        expected = f'postgresql://{POSTGRES_USER}@localhost/pgosm?application_name=pgosm-flex'
        result = db.connection_string(db_name='pgosm')
        self.assertEqual(expected, result)


    @mock.patch.dict(os.environ, PG_USER_AND_PW)
    def test_connection_string_user_w_pw_returns_expected_string(self):
        expected = f'postgresql://{POSTGRES_USER}:{POSTGRES_PASSWORD}@localhost/pgosm?application_name=pgosm-flex'
        result = db.connection_string(db_name='pgosm')
        self.assertEqual(expected, result)
