""" Unit tests to cover the DB module."""
import os
import unittest
from unittest import mock

import db

POSTGRES_USER = 'my_pg_user'
POSTGRES_PASSWORD = 'here_for_fun!@#$%^&*()'
POSTGRES_HOST_EXTERNAL = 'not-intented-to-be-real'

PG_USER_ONLY = {'POSTGRES_USER': POSTGRES_USER,
                'POSTGRES_PASSWORD': ''}
PG_USER_AND_PW = {'POSTGRES_USER': POSTGRES_USER,
                  'POSTGRES_PASSWORD': POSTGRES_PASSWORD,
                  'PGOSM_CONN_PG': db.connection_string(admin=True),
                  'PGOSM_CONN': db.connection_string()}
POSTGRES_HOST_NON_LOCAL = {'POSTGRES_HOST': POSTGRES_HOST_EXTERNAL,
                           'POSTGRES_USER': POSTGRES_USER,
                           'POSTGRES_PASSWORD': POSTGRES_PASSWORD}


class DBTests(unittest.TestCase):

    @mock.patch.dict(os.environ, PG_USER_ONLY)
    def test_pg_conn_parts_user_only_returns_expected_values(self):
        expected_user = POSTGRES_USER
        expected_pw = None
        results = db.pg_conn_parts()
        self.assertEqual(expected_user, results['pg_user'])
        self.assertEqual(expected_pw, results['pg_pass'])


    @mock.patch.dict(os.environ, PG_USER_AND_PW)
    def test_pg_conn_parts_user_w_pw_returns_expected_values(self):
        expected_user = POSTGRES_USER
        expected_pw = POSTGRES_PASSWORD
        results = db.pg_conn_parts()
        self.assertEqual(expected_user, results['pg_user'])
        self.assertEqual(expected_pw, results['pg_pass'])


    @mock.patch.dict(os.environ, PG_USER_ONLY)
    def test_connection_string_user_only_returns_expected_string(self):
        expected = f"dbname='pgosm' user='{POSTGRES_USER}' host='localhost' port='5432' application_name='pgosm-flex'"
        result = db.connection_string()
        self.assertEqual(expected, result)


    @mock.patch.dict(os.environ, PG_USER_AND_PW)
    def test_connection_string_user_w_pw_returns_expected_string(self):
        expected = f"dbname='pgosm' user='{POSTGRES_USER}' password='{POSTGRES_PASSWORD}' host='localhost' port='5432' application_name='pgosm-flex'"
        result = db.connection_string()
        self.assertEqual(expected, result)


    @mock.patch.dict(os.environ, POSTGRES_HOST_NON_LOCAL)
    def test_admin_connection_string_external_returns_expected_string(self):
        """Non-Docker Postgres connection uses the same connection string for
        standard & admin connections. Only use of admin connection w/ external
        Postgres is version check.
        """
        expected = f"dbname='pgosm' user='{POSTGRES_USER}' password='{POSTGRES_PASSWORD}' host='{POSTGRES_HOST_EXTERNAL}' port='5432' application_name='pgosm-flex'"
        result_standard = db.connection_string()
        result_admin = db.connection_string(admin=True)
        self.assertEqual(expected, result_standard)
        self.assertEqual(expected, result_admin)


    @mock.patch.dict(os.environ, POSTGRES_HOST_NON_LOCAL)
    def test_drop_pgosm_db_with_non_localhost_returns_False(self):
        """Tests the function returns False instead of attempting to drop the DB
        """
        expected = False
        result = db.drop_pgosm_db()
        self.assertEqual(expected, result)


    @mock.patch.dict(os.environ, POSTGRES_HOST_NON_LOCAL)
    def test_create_pgosm_db_with_non_localhost_returns_False(self):
        """Tests the function returns False instead of attempting to create the DB
        """
        expected = False
        result = db.create_pgosm_db()
        self.assertEqual(expected, result)


    @mock.patch.dict(os.environ, PG_USER_AND_PW)
    def test_pg_version_check_returns_int(self):
        expected = int
        result = db.pg_version_check()
        self.assertEqual(expected, type(result))


    @mock.patch.dict(os.environ, PG_USER_AND_PW)
    def test_get_prior_import_returns_expected_type(self):
        result = db.get_prior_import(schema_name='osm')
        actual = type(result)
        expected = dict
        self.assertEqual(expected, actual)