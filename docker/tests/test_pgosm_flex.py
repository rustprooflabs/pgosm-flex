""" Unit tests to cover the DB module."""
import unittest
import pgosm_flex

REGION_US = 'north-america/us'
SUBREGION_DC = 'district-of-columbia'

class PgOSMFlexTests(unittest.TestCase):

    def test_get_region_filename_returns_subregion_when_exists(self):
        region = REGION_US
        subregion = SUBREGION_DC
        result = pgosm_flex.get_region_filename(region, subregion)
        expected = f'{SUBREGION_DC}-latest.osm.pbf'
        self.assertEqual(expected, result)

    def test_get_region_filename_returns_region_when_subregion_None(self):
        region = REGION_US
        subregion = None
        result = pgosm_flex.get_region_filename(region, subregion)
        expected = f'{REGION_US}-latest.osm.pbf'
        self.assertEqual(expected, result)


    def test_get_pbf_url_returns_proper_with_region_and_subregion(self):
        region = REGION_US
        subregion = SUBREGION_DC
        result = pgosm_flex.get_pbf_url(region, subregion)
        expected = f'https://download.geofabrik.de/{region}/{subregion}-latest.osm.pbf'
        self.assertEqual(expected, result)

    def test_get_pbf_url_returns_proper_with_region_and_subregion(self):
        region = REGION_US
        subregion = None
        result = pgosm_flex.get_pbf_url(region, subregion)
        expected = f'https://download.geofabrik.de/{region}-latest.osm.pbf'
        self.assertEqual(expected, result)

