""" Unit tests to cover the osm2pgsql_recommendation module."""
import os
import unittest

import osm2pgsql_recommendation


class Osm2pgsqlRecommendationTests(unittest.TestCase):

    def test_get_recommended_script_returns_str(self):
        expected = str
        system_ram_gb = 1
        osm_pbf_gb = 10
        append = False
        pbf_filename = 'This-is-a-test.osm.pbf'
        pgosm_layer_set = 'default'
        output_path = 'this-is-a-test'
        result = osm2pgsql_recommendation.get_recommended_script(system_ram_gb,
                                                                 osm_pbf_gb,
                                                                 append,
                                                                 pbf_filename,
                                                                 pgosm_layer_set,
                                                                 output_path)
        actual = type(result)
        self.assertEqual(expected, actual)

    def test_get_recommended_script_returns_expected_str(self):
        expected = 'osm2pgsql -d postgresql://postgres:mysecretpassword@localhost/pgosm?application_name=pgosm-flex  --cache=0  --slim  --drop  --flat-nodes=/tmp/nodes  --output=flex --style=./default.lua  this-is-a-test/This-is-a-test.osm.pbf'
        system_ram_gb = 1
        osm_pbf_gb = 10
        append = False
        pbf_filename = 'This-is-a-test.osm.pbf'
        pgosm_layer_set = 'default'
        output_path = 'this-is-a-test'
        actual = osm2pgsql_recommendation.get_recommended_script(system_ram_gb,
                                                                 osm_pbf_gb,
                                                                 append,
                                                                 pbf_filename,
                                                                 pgosm_layer_set,
                                                                 output_path)
        self.assertEqual(expected, actual)
