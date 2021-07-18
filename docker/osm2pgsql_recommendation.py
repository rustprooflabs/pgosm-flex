"""Used by PgOSM-Flex Docker image to get osm2pgsql command to run from
the osm2pgsql-tuner API.

Usage:
    python3 osm2pgsql_recommendation.py colorado 8
"""
import os
import sys
import requests
import click


@click.command()
@click.option('--region', required=True,
              prompt="Region name",
              help='Region name matching the filename for data sourced from Geofabrik. e.g. district-of-columbia')
@click.option('--ram', required=True,
              prompt="System RAM (GB)",
              help='Total system RAM available in GB')
@click.option('--output', required=True,
              prompt="Ouptut path",
              help='Output path')
@click.option('--layerset', default='run-all',
              prompt="PgOSM Flex layer set",
              help='Layer set from PgOSM Flex.  e.g. run-all, run-no-tags')
def osm2pgsql_recommendation(region, ram, output, layerset):
    """Writes osm2pgsql recommendation to disk.

    Recommendation from osm2pgsql-tuner.com.
    """
    region_name = region
    system_ram_gb = ram
    output_path = output
    pgosm_layer_set = layerset

    pbf_filename = f'{region_name}-latest'
    pbf_file = f'{pbf_filename}.osm.pbf'
    print(pbf_file)

    osm_pbf_gb = os.path.getsize(pbf_file) / 1024 / 1024 / 1024

    # PgOSM-Flex currently does not support/test append mode.
    append = False

    osm2pgsql_cmd = get_recommended_script(system_ram_gb,
                                           osm_pbf_gb,
                                           append,
                                           pbf_filename,
                                           pgosm_layer_set,
                                           output_path)

    script_filename = f'osm2pgsql-{region_name}.sh'
    osm2pgsql_script_path = os.path.join(output_path, script_filename)

    with open(osm2pgsql_script_path,'w') as out_script:
        out_script.write(osm2pgsql_cmd)
        out_script.write('\n')


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


if __name__ == '__main__':
    osm2pgsql_recommendation()

