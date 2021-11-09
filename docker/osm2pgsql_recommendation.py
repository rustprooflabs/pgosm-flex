"""Used by PgOSM-Flex Docker image to get osm2pgsql command to run from
the osm2pgsql-tuner API.
"""
import logging
import os
import osm2pgsql_tuner as tuner
import re

import db

LOGGER = logging.getLogger('pgosm-flex')


def osm2pgsql_recommendation(ram, pbf_filename, out_path):
    """Returns recommended osm2pgsql command.

    Recommendation from API at https://osm2pgsql-tuner.com

    Parameters
    ----------------------
    ram : float
        Total system RAM available in GB

    pbf_filename : str

    out_path : str

    Returns
    ----------------------
    osm2pgsql_cmd : str
    """
    system_ram_gb = ram
    # The layerset is now set via env var.  This is used to set filename for osm2pgsql command
    pgosm_layer_set = 'run'
    if not os.path.isabs(pbf_filename):
        pbf_file = os.path.join(out_path, pbf_filename)
    else:
        pbf_file = pbf_filename
    osm_pbf_gb = os.path.getsize(pbf_file) / 1024 / 1024 / 1024
    LOGGER.info(f'PBF size (GB): {osm_pbf_gb}')

    # PgOSM-Flex currently does not support/test append mode.
    append = False
    osm2pgsql_cmd = get_recommended_script(system_ram_gb,
                                           osm_pbf_gb,
                                           append,
                                           pbf_file,
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
    LOGGER.debug(f'Generating recommended osm2pgsql command')

    rec = tuner.recommendation(system_ram_gb=system_ram_gb,
                               osm_pbf_gb=osm_pbf_gb,
                               append=append,
                               ssd=True,
                               pgosm_layer_set=pgosm_layer_set)

    # FIXME: Currently requires .osm.pbf input. Will block full functionality of #192
    filename_no_ext = pbf_filename.replace('.osm.pbf', '')
    osm2pgsql_cmd = rec.get_osm2pgsql_command(out_format='api',
                                             pbf_filename=filename_no_ext)
    LOGGER.info(f'Generic command to run: {osm2pgsql_cmd}')

    # Replace generic path from API with specific path
    osm2pgsql_cmd = re.sub(r'~/pgosm-data[^ ]+', pbf_filename, osm2pgsql_cmd)
    # Replace generic connection string with specific conn string
    conn_string = db.connection_string(db_name='pgosm')
    osm2pgsql_cmd = osm2pgsql_cmd.replace('-d $PGOSM_CONN',
                                          f'-d {conn_string}')
    return osm2pgsql_cmd
