""" Unit tests to cover the osm2pgsql_recommendation module."""
import os
import unittest

import osm2pgsql_recommendation
from import_mode import ImportMode


class Osm2pgsqlRecommendationTests(unittest.TestCase):

    def test_get_recommended_script_returns_type_str(self):
        expected = str
        system_ram_gb = 2
        osm_pbf_gb = 10
        im = ImportMode(replication=False,
                        replication_update=False,
                        update=None)
        pbf_filename = 'This-is-a-test.osm.pbf'
        output_path = 'this-is-a-test'
        result = osm2pgsql_recommendation.get_recommended_script(system_ram_gb=system_ram_gb,
                                                                 osm_pbf_gb=osm_pbf_gb,
                                                                 import_mode=im,
                                                                 pbf_filename=pbf_filename,
                                                                 output_path=output_path)

        actual = type(result)
        self.assertEqual(expected, actual)

    def test_get_recommended_script_returns_expected_value_str(self):
        expected = 'osm2pgsql -d postgresql://postgres:mysecretpassword@localhost:5432/pgosm?application_name=pgosm-flex  --cache=0  --slim  --drop  --flat-nodes=/tmp/nodes  --create  --output=flex --style=./run.lua  This-is-a-test.osm.pbf'
        system_ram_gb = 2
        osm_pbf_gb = 10
        im = ImportMode(replication=False,
                        replication_update=False,
                        update=None)
        pbf_filename = 'This-is-a-test.osm.pbf'
        output_path = 'this-is-a-test'
        actual = osm2pgsql_recommendation.get_recommended_script(system_ram_gb=system_ram_gb,
                                                                 osm_pbf_gb=osm_pbf_gb,
                                                                 import_mode=im,
                                                                 pbf_filename=pbf_filename,
                                                                 output_path=output_path)
        self.assertEqual(expected, actual)
