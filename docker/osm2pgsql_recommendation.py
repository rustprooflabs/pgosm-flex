"""Used by PgOSM-Flex Docker image to get osm2pgsql command to run from
the osm2pgsql-tuner API.
"""
import os
import requests

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

    osm_pbf_gb = os.path.getsize(pbf_filename) / 1024 / 1024 / 1024

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
    api_endpoint = 'https://osm2pgsql-tuner.com/api/v1'
    api_endpoint += f'?system_ram_gb={system_ram_gb}'
    api_endpoint += f'&osm_pbf_gb={osm_pbf_gb}'
    api_endpoint += f'&append={append}'
    api_endpoint += f'&pbf_filename={pbf_filename}'
    api_endpoint += f'&pgosm_layer_set={pgosm_layer_set}'

    headers = {"User-Agent": 'PgOSM-Flex-Docker'}
    print(f'osm2pgsql-tuner URL w/ parameters: {api_endpoint}')
    result = requests.get(api_endpoint, headers=headers)
    print(f'Status code: {result.status_code}')

    rec = result.json()['osm2pgsql']

    osm2pgsql_cmd = rec['cmd']
    osm2pgsql_cmd = osm2pgsql_cmd.replace('~/pgosm-data/', output_path)
    osm2pgsql_cmd = osm2pgsql_cmd.replace('-d $PGOSM_CONN',
                                          '-U postgres -d pgosm')
    return osm2pgsql_cmd
