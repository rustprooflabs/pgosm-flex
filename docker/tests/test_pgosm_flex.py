""" Unit tests to cover the DB module."""
import unittest
import pgosm_flex, helpers

REGION_US = 'north-america/us'
SUBREGION_DC = 'district-of-columbia'
LAYERSET = 'default'
PGOSM_DATE = '2021-12-02'


class PgOSMFlexTests(unittest.TestCase):

    def setUp(self):
        helpers.set_env_vars(region=REGION_US,
                             subregion=SUBREGION_DC,
                             srid=3857,
                             language=None,
                             pgosm_date=PGOSM_DATE,
                             layerset=LAYERSET,
                             layerset_path=None)


    def tearDown(self):
        helpers.unset_env_vars()

    def test_get_paths_returns_dict(self):
        expected = dict
        actual = pgosm_flex.get_paths()
        self.assertEqual(expected, type(actual))


    def test_validate_region_inputs_raises_ValueError_no_region_or_input(self):
        region = None
        subregion = None
        input_file = None

        with self.assertRaises(ValueError):
            pgosm_flex.validate_region_inputs(region, subregion, input_file)


    def test_validate_region_inputs_raises_ValueError_subregion_wout_region(self):
        region = None
        subregion = 'subregion-value'
        input_file = 'some-value'

        with self.assertRaises(ValueError):
            pgosm_flex.validate_region_inputs(region, subregion, input_file)

    def test_validate_region_inputs_raises_ValueError_region_should_have_subregion(self):
        region = 'north-america/us'
        subregion = None
        input_file = None

        with self.assertRaises(ValueError):
            pgosm_flex.validate_region_inputs(region, subregion, input_file)

    def test_get_export_full_path_returns_expected_str(self):
        export_filename = 'relative-path'
        out_path = '/tmp/not/real'
        expected = f'{out_path}/{export_filename}'
        result = pgosm_flex.get_export_full_path(out_path, export_filename)
        self.assertEqual(expected, result)

    def test_get_export_filename_slash_to_dash(self):
        """Ensure region & subregion have slash "/" changed to dash "-"

        Also tests the filename w/ region & subregion - no need for an additional
        test covering that behavior.
        """
        input_file = None
        result = pgosm_flex.get_export_filename(input_file)
        expected = 'north-america-us-district-of-columbia-default-2021-12-02.sql'
        self.assertEqual(expected, result)

    def test_get_export_filename_input_file_defined_overrides_region_subregion(self):
        input_file = '/my/inputfile.osm.pbf'
        result = pgosm_flex.get_export_filename(input_file)
        expected = '/my/inputfile-default-2021-12-02.sql'
        self.assertEqual(expected, result)

    def test_get_export_filename_region_only(self):
        # Override Subregion to None
        helpers.unset_env_vars()
        helpers.set_env_vars(region='north-america',
                             subregion=None,
                             srid=3857,
                             language=None,
                             pgosm_date=PGOSM_DATE,
                             layerset=LAYERSET,
                             layerset_path=None)

        input_file = None
        result = pgosm_flex.get_export_filename(input_file)
        expected = 'north-america-default-2021-12-02.sql'
        self.assertEqual(expected, result)

