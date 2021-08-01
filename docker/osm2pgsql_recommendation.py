"""Used by PgOSM-Flex Docker image to get osm2pgsql command to run from
the osm2pgsql-tuner API.
"""
import logging
import os
import requests

import db

LOGGER = logging.getLogger('pgosm-flex')


def osm2pgsql_recommendation(region, ram, layerset, pbf_filename,
                             out_path):
    """Writes osm2pgsql recommendation to disk.

    Recommendation from https://osm2pgsql-tuner.com

    Parameters
    ----------------------
    region : str
        Region name matching the filename for data sourced from Geofabrik.
        e.g. district-of-columbia

    ram : float
        Total system RAM available in GB

    layerset : str
        Layer set from PgOSM Flex.  e.g. run-all, run-no-tags
    """
    region_name = region
    system_ram_gb = ram
    pgosm_layer_set = layerset

    pbf_file = os.path.join(out_path, pbf_filename)
    osm_pbf_gb = os.path.getsize(pbf_file) / 1024 / 1024 / 1024
    LOGGER.info(f'PBF size (GB): {osm_pbf_gb}')

    # PgOSM-Flex currently does not support/test append mode.
    append = False

    osm2pgsql_cmd = get_recommended_script(system_ram_gb,
                                           osm_pbf_gb,
                                           append,
                                           pbf_filename,
                                           pgosm_layer_set,
                                           out_path)

    return osm2pgsql_cmd

def get_recommended_script(system_ram_gb, osm_pbf_gb,
                           append, pbf_filename,
                           pgosm_layer_set,
                           output_path):
    """Builds API call and cleans up returned command for use here.

    Parameters
    -------------------------------
    system_ram_gb : float
    osm_pbf_gb : float
    append : bool
    pbf_filename : str
    pgosm_layer_set : str
    output_path : str

    Returns
    -------------------------------
    osm2pgsql_cmd : str
    """
    filename_no_ext = pbf_filename.replace('.osm.pbf', '')
    api_endpoint = 'https://osm2pgsql-tuner.com/api/v1'
    api_endpoint += f'?system_ram_gb={system_ram_gb}'
    api_endpoint += f'&osm_pbf_gb={osm_pbf_gb}'
    api_endpoint += f'&append={append}'
    api_endpoint += f'&pbf_filename={filename_no_ext}'
    api_endpoint += f'&pgosm_layer_set={pgosm_layer_set}'

    headers = {"User-Agent": 'PgOSM-Flex-Docker'}
    LOGGER.info(f'osm2pgsql-tuner URL w/ parameters: {api_endpoint}')
    result = requests.get(api_endpoint, headers=headers)
    LOGGER.debug(f'API status code: {result.status_code}')

    rec = result.json()['osm2pgsql']

    osm2pgsql_cmd = rec['cmd']
    # Replace generic path from API with specific path
    osm2pgsql_cmd = osm2pgsql_cmd.replace('~/pgosm-data', output_path)

    # Replace generic connection string with specific conn string
    conn_string = db.connection_string(db_name='pgosm')
    osm2pgsql_cmd = osm2pgsql_cmd.replace('-d $PGOSM_CONN',
                                          f'-d {conn_string}')
    return osm2pgsql_cmd
