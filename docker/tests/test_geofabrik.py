""" Unit tests to cover the Geofabrik module."""
import unittest
import geofabrik

REGION_US = 'north-america/us'
SUBREGION_DC = 'district-of-columbia'


class GeofabrikTests(unittest.TestCase):

    def test_get_region_filename_returns_subregion_when_exists(self):
        region = REGION_US
        subregion = SUBREGION_DC
        result = geofabrik.get_region_filename(region, subregion)
        expected = f'{SUBREGION_DC}-latest.osm.pbf'
        self.assertEqual(expected, result)

    def test_get_region_filename_returns_region_when_subregion_None(self):
        region = REGION_US
        subregion = None
        result = geofabrik.get_region_filename(region, subregion)
        expected = f'{REGION_US}-latest.osm.pbf'
        self.assertEqual(expected, result)

    def test_get_pbf_url_returns_proper_with_region_and_subregion(self):
        region = REGION_US
        subregion = SUBREGION_DC
        result = geofabrik.get_pbf_url(region, subregion)
        expected = f'https://download.geofabrik.de/{region}/{subregion}-latest.osm.pbf'
        self.assertEqual(expected, result)

    def test_get_pbf_url_returns_proper_with_region_and_subregion(self):
        region = REGION_US
        subregion = None
        result = geofabrik.get_pbf_url(region, subregion)
        expected = f'https://download.geofabrik.de/{region}-latest.osm.pbf'
        self.assertEqual(expected, result)

    def test_pbf_download_needed_returns_boolean(self):
        region = REGION_US
        subregion = SUBREGION_DC
        pgosm_date = geofabrik.helpers.get_today()
        region_filename = geofabrik.get_region_filename(region, subregion)
        expected = bool
        result = geofabrik.pbf_download_needed(pbf_file_with_date='does-not-matter',
                                               md5_file_with_date='not-a-file',
                                               pgosm_date=pgosm_date)
        self.assertEqual(expected, type(result))

    def test_pbf_download_needed_returns_true_when_file_not_exists(self):
        region = REGION_US
        subregion = SUBREGION_DC
        pgosm_date = geofabrik.helpers.get_today()
        region_filename = geofabrik.get_region_filename(region, subregion)
        expected = True
        result = geofabrik.pbf_download_needed(pbf_file_with_date='does-not-matter',
                                               md5_file_with_date='not-a-file',
                                               pgosm_date=pgosm_date)
        self.assertEqual(expected, result)


