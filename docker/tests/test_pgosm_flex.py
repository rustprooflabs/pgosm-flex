""" Unit tests to cover the DB module."""
import unittest
import pgosm_flex

REGION_US = 'north-america/us'
SUBREGION_DC = 'district-of-columbia'

class PgOSMFlexTests(unittest.TestCase):

    def test_get_paths_returns_dict(self):
        base_path = pgosm_flex.BASE_PATH_DEFAULT
        expected = dict
        actual = pgosm_flex.get_paths(base_path=base_path)
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
