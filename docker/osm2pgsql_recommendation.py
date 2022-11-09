"""Used by PgOSM-Flex Docker image to get osm2pgsql command to run from
the osm2pgsql-tuner API.
"""
import logging
import os
import osm2pgsql_tuner as tuner

import db

LOGGER = logging.getLogger('pgosm-flex')


def osm2pgsql_recommendation(ram, pbf_filename, out_path, append):
    """Returns recommended osm2pgsql command.

    Recommendation from API at https://osm2pgsql-tuner.com

    Parameters
    ----------------------
    ram : float
        Total system RAM available in GB

    pbf_filename : str

    out_path : str

    append : boolean

    Returns
    ----------------------
    osm2pgsql_cmd : str
    """
    system_ram_gb = ram

    if not os.path.isabs(pbf_filename):
        pbf_file = os.path.join(out_path, pbf_filename)
    else:
        pbf_file = pbf_filename

    osm_pbf_gb = os.path.getsize(pbf_file) / 1024 / 1024 / 1024
    LOGGER.debug(f'PBF size (GB): {osm_pbf_gb}')

    osm2pgsql_cmd = get_recommended_script(system_ram_gb,
                                           osm_pbf_gb,
                                           append,
                                           pbf_file,
                                           out_path)
    return osm2pgsql_cmd

def get_recommended_script(system_ram_gb, osm_pbf_gb, append, pbf_filename,
                           output_path):
    """Generates recommended osm2pgsql command from osm2pgsql-tuner.

    Parameters
    -------------------------------
    system_ram_gb : float
    osm_pbf_gb : float
    append : bool
    pbf_filename : str
        Can be filename or absolute path.
    output_path : str

    Returns
    -------------------------------
    osm2pgsql_cmd : str
        The osm2pgsql command to run, customized for this run of pgosm flex.

        Warning: Do not print this string, it includes password in the
        connection string. Might not matter too much with in-docker use and
        throwaway containers/passwords, but intend to support external Postgres
        connections.
    """
    LOGGER.debug('Generating recommended osm2pgsql command')

    rec = tuner.recommendation(system_ram_gb=system_ram_gb,
                               osm_pbf_gb=osm_pbf_gb,
                               append=append,
                               ssd=True)

    osm2pgsql_cmd = rec.get_osm2pgsql_command(out_format='api',
                                              pbf_path=pbf_filename)

    osm2pgsql_cmd = osm2pgsql_cmd.replace('~/pgosm-data', output_path)

    LOGGER.info(f'Generic command to run: {osm2pgsql_cmd}')

    # Replace generic connection string with specific conn string
    conn_string = db.connection_string()
    osm2pgsql_cmd = osm2pgsql_cmd.replace('-d $PGOSM_CONN', f'-d {conn_string}')
    # Warning: Do not print() this string any more! Includes password
    return osm2pgsql_cmd
