#!/usr/bin/env python3
"""Python script to run PgOSM Flex.

Designed to be ran in Docker image:
    https://hub.docker.com/r/rustprooflabs/pgosm-flex
"""
import configparser
import logging
import os
from pathlib import Path
import sys
import subprocess

import click

import osm2pgsql_recommendation as rec
import db, geofabrik, helpers


BASE_PATH_DEFAULT = '/app'
"""Default path for pgosm-flex project for Docker.
"""

DEFAULT_SRID = '3857'


@click.command()
# Required and most common options first
@click.option('--ram', required=True,
              type=float,
              help='Amount of RAM in GB available on the machine running this process. Used to determine appropriate osm2pgsql command via osm2pgsql-tuner recommendation engine.')
@click.option('--region', required=False,
              help='Region name matching the filename for data sourced from Geofabrik. e.g. north-america/us. Optional when --input-file is specified, otherwise required.')
@click.option('--subregion', required=False,
              help='Sub-region name matching the filename for data sourced from Geofabrik. e.g. district-of-columbia')
# Remainder of options in alphabetical order
@click.option('--basepath',
              required=False,
              default=BASE_PATH_DEFAULT,
              help='Debugging option. Used when testing locally and not within Docker')
@click.option('--data-only',
              default=False,
              envvar="PGOSM_DATA_SCHEMA_ONLY",
              is_flag=True,
              help="When set, skips running Sqitch and importing QGIS Styles.")
@click.option('--debug', is_flag=True,
              help='Enables additional log output')
@click.option('--input-file',
              required=False,
              default=None,
              help='Set explicit filepath to input osm.pbf file. Overrides default file handling, archiving, and MD5 checksum.')
@click.option('--layerset', required=True,
              default='default',
              help='Layerset to load. Defines name of included layerset unless --layerset-path is defined.')
@click.option('--layerset-path', required=False,
              help='Custom path to load layerset INI from. Custom paths should be mounted to Docker via docker run -v ...')
@click.option('--language', default=None,
              envvar="PGOSM_LANGUAGE",
              help="Set default language in loaded OpenStreetMap data when available.  e.g. 'en' or 'kn'.")
@click.option('--pgosm-date', required=False,
              default=helpers.get_today(),
              envvar="PGOSM_DATE",
              help="Date of the data in YYYY-MM-DD format. If today (default), automatically downloads when files not found locally. Set to historic date to load locally archived PBF/MD5 file, will fail if both files do not exist.")
@click.option('--schema-name', required=False,
              default='osm',
              help="Change the final schema name, defaults to 'osm'.")
@click.option('--skip-dump', default=False, is_flag=True,
              help='Skips the final pg_dump at the end. Useful for local testing when not loading into more permanent instance.')
@click.option('--skip-nested',
              default=False,
              envvar="PGOSM_SKIP_NESTED_POLYGON",
              is_flag=True,
              help='When set, skips calculating nested admin polygons. Can be time consuming on large regions.')
@click.option('--srid', required=False, default=DEFAULT_SRID,
              envvar="PGOSM_SRID",
              help="SRID for data loaded by osm2pgsql to PostGIS. Defaults to 3857")
def run_pgosm_flex(layerset, layerset_path, ram, region, subregion, srid,
                    pgosm_date, language, schema_name, skip_nested, data_only,
                    skip_dump, debug, basepath, input_file):
    """Run PgOSM Flex within Docker to automate osm2pgsql flex processing.
    """
    paths = get_paths(base_path=basepath)
    setup_logger(debug)
    logger = logging.getLogger('pgosm-flex')
    logger.info('PgOSM Flex starting...')

    validate_region_inputs(region, subregion, input_file)

    # Ensure always a region name
    if region is None and input_file:
        region = input_file

    set_env_vars(region, subregion, srid, language, pgosm_date,
                 layerset, layerset_path)

    if input_file is None:
        geofabrik.prepare_data(region=region,
                               subregion=subregion,
                               pgosm_date=pgosm_date,
                               out_path=paths['out_path'])

        pbf_filename = geofabrik.get_region_filename(region, subregion)
        osm2pgsql_command = rec.osm2pgsql_recommendation(ram=ram,
                                           pbf_filename=pbf_filename,
                                           out_path=paths['out_path'])
    else:
        osm2pgsql_command = rec.osm2pgsql_recommendation(ram=ram,
                                           pbf_filename=input_file,
                                           out_path=paths['out_path'])

    db.wait_for_postgres()

    db.prepare_pgosm_db(data_only=data_only, db_path=paths['db_path'])

    flex_path = paths['flex_path']
    run_osm2pgsql(osm2pgsql_command=osm2pgsql_command,
                  flex_path=flex_path)

    if not skip_nested:
        # Auto-set skip_nested when place layer not imported
        skip_nested = check_layerset_places(layerset_path, layerset, flex_path)

    run_post_processing(flex_path=flex_path, skip_nested=skip_nested)

    if input_file is None:
        geofabrik.remove_latest_files(region, subregion, paths)

    export_filename = get_export_filename(region,
                                          subregion,
                                          layerset,
                                          pgosm_date,
                                          input_file)

    export_path = get_export_full_path(paths['out_path'], export_filename)

    if schema_name != 'osm':
        db.rename_schema(schema_name)

    if skip_dump:
        logger.info('Skipping pg_dump')
    else:
        db.run_pg_dump(export_path=export_path,
                       data_only=data_only,
                       schema_name=schema_name)
    logger.info('PgOSM Flex complete!')


def validate_region_inputs(region, subregion, input_file):
    """Ensures the combination of region, subregion and input_file is valid.

    No return, raises error when invalid.

    Parameters
    -----------------------
    region : str
    subregion : str
    input_file : str
    """
    if region is None and input_file is None:
        raise ValueError('Either --region or --input-file must be provided')

    if region is None and subregion is not None:
        raise ValueError('Cannot use --subregion without --region')

    if region is not None:
        if '/' in region and subregion is None:
            err_msg = 'Region provided appears to include subregion. '
            err_msg += 'The portion after the final "/" in the Geofabrik URL '
            err_msg += 'should be the --subregion.'
            raise ValueError(err_msg)


def set_env_vars(region, subregion, srid, language, pgosm_date, layerset,
                 layerset_path):
    """Sets environment variables needed by PgOSM Flex.

    See /docs/MANUAL-STEPS-RUN.md for usage examples of environment variables.

    Parameters
    ------------------------
    region : str
    subregion : str
    srid : str
    language : str
    pgosm_date : str
    layerset : str
    layerset_path : str
        str when set, or None
    """
    logger = logging.getLogger('pgosm-flex')
    logger.debug('Ensuring env vars are not set from prior run')
    unset_env_vars()
    logger.debug('Setting environment variables')

    if subregion is None:
        pgosm_region = f'{region}'
    else:
        pgosm_region = f'{region}-{subregion}'

    logger.info(f'PGOSM_REGION: {pgosm_region}')
    os.environ['PGOSM_REGION'] = pgosm_region

    if srid != DEFAULT_SRID:
        logger.info(f'SRID set: {srid}')
        os.environ['PGOSM_SRID'] = str(srid)
    if language is not None:
        logger.info(f'Language set: {language}')
        os.environ['PGOSM_LANGUAGE'] = str(language)

    if layerset_path is not None:
        logger.info(f'Custom layerset path set: {layerset_path}')
        os.environ['PGOSM_LAYERSET_PATH'] = str(layerset_path)

    os.environ['PGOSM_DATE'] = pgosm_date
    os.environ['PGOSM_LAYERSET'] = layerset
    # PGOSM_CONN is required by Lua scripts for osm2pgsql. This should
    # be the only place a connection string is defined outside of Sqitch usage.
    os.environ['PGOSM_CONN'] = db.connection_string(db_name='pgosm')
    # Connection to DB for admin purposes, e.g. drop/create main database
    os.environ['PGOSM_CONN_PG'] = db.connection_string(db_name='postgres')


def unset_env_vars():
    """Unsets environment variables used by PgOSM Flex.
    """
    os.environ.pop('PGOSM_REGION', None)
    os.environ.pop('PGOSM_SRID', None)
    os.environ.pop('PGOSM_LANGUAGE', None)
    os.environ.pop('PGOSM_LAYERSET_PATH', None)
    os.environ.pop('PGOSM_DATE', None)
    os.environ.pop('PGOSM_LAYERSET', None)
    os.environ.pop('PGOSM_CONN', None)
    os.environ.pop('PGOSM_CONN_PG', None)


def setup_logger(debug):
    """Prepares logging.

    Parameters
    ------------------------------
    debug : bool
        Enables debug mode when True.  INFO when False.
    """
    if debug:
        log_level = logging.DEBUG
    else:
        log_level = logging.INFO

    log_format = '%(asctime)s:%(levelname)s:%(name)s:%(module)s:%(message)s'
    logging.basicConfig(stream=sys.stdout,
                        level=log_level,
                        filemode='w',
                        format=log_format)

    # Reduce verbosity of urllib3 logging
    logging.getLogger('urllib3').setLevel(logging.INFO)

    logger = logging.getLogger('pgosm-flex')
    logger.debug('Logger configured')



def get_paths(base_path):
    """Returns dictionary of various paths used.

    Ensures `out_path` exists.

    Parameters
    -------------------
    base_path : str

    Returns
    -------------------
    paths : dict
    """
    db_path = os.path.join(base_path, 'db')
    out_path = os.path.join(base_path, 'output')
    flex_path = os.path.join(base_path, 'flex-config')
    paths = {'base_path': base_path,
             'db_path': db_path,
             'out_path': out_path,
             'flex_path': flex_path}

    Path(out_path).mkdir(parents=True, exist_ok=True)
    return paths



def get_export_filename(region, subregion, layerset, pgosm_date, input_file):
    """Returns the .sql filename to use for pg_dump.

    Parameters
    ----------------------
    region : str
    subregion : str
    layerset : str
    pgosm_date : str
    input_file : str

    Returns
    ----------------------
    filename : str
    """
    # region is always set internally, even with --input-file and no --region
    region = region.replace('/', '-')
    if subregion:
        subregion = subregion.replace('/', '-')

    if input_file:
        # Assumes .osm.pbf
        base_name = input_file[:-8]
        filename = f'{base_name}-{layerset}-{pgosm_date}.sql'
    elif subregion is None:
        filename = f'{region}-{layerset}-{pgosm_date}.sql'
    else:
        filename = f'{region}-{subregion}-{layerset}-{pgosm_date}.sql'

    return filename


def get_export_full_path(out_path, export_filename):
    """If `export_filename` is an absolute path, `out_path` is not considered.

    Parameters
    -----------------
    out_path : str
    export_filename : str

    Returns
    -----------------
    export_path : str
    """

    if os.path.isabs(export_filename):
        export_path = export_filename
    else:
        export_path = os.path.join(out_path, export_filename)

    return export_path


def run_osm2pgsql(osm2pgsql_command, flex_path):
    """Runs the provided osm2pgsql command.

    Parameters
    ----------------------
    osm2pgsql_command : str
    flex_path : str
    """
    logger = logging.getLogger('pgosm-flex')
    logger.info('Running osm2pgsql')

    output = subprocess.run(osm2pgsql_command.split(),
                            text=True,
                            cwd=flex_path,
                            check=False,
                            stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)

    logger.info(f'osm2pgsql output: \n {output.stdout}\nEND PgOSM Flex output')

    if output.returncode != 0:
        err_msg = f'Failed to run osm2pgsql. Return code: {output.returncode}'
        logger.error(err_msg)
        sys.exit(f'{err_msg} - Check the log output for details.')

    logger.info('osm2pgsql completed.')


def check_layerset_places(layerset_path, layerset, flex_path):
    """If `place` layer is not included `skip_nested` should be true.

    Parameters
    ------------------------
    layerset_path : str
    layerset : str
    flex_path : str

    Returns
    ------------------------
    skip_nested : boolean
    """
    logger = logging.getLogger('pgosm-flex')

    if layerset_path is None:
        layerset_path = os.path.join(flex_path, 'layerset')
        logger.info(f'Using default layerset path {layerset_path}')

    ini_file = os.path.join(layerset_path, f'{layerset}.ini')
    config = configparser.ConfigParser()
    config.read(ini_file)
    try:
        place = config['layerset']['place']
    except KeyError:
        logger.debug('Place layer not defined, setting skip_nested')
        return True

    if place:
        logger.debug('Place layer is defined as true. Not setting skip_nested')
        return False

    logger.debug('Place set to false, setting skip_nested')
    return True


def run_post_processing(flex_path, skip_nested):
    """Runs steps following osm2pgsql import.

    Post-processing SQL scripts and (optionally) calculate nested admin polgyons

    Parameters
    ----------------------
    flex_path : str

    skip_nested : bool
    """
    db.pgosm_after_import(flex_path)
    logger = logging.getLogger('pgosm-flex')
    if skip_nested:
        logger.info('Skipping calculating nested polygons')
    else:
        logger.info('Calculating nested polygons')
        db.pgosm_nested_admin_polygons(flex_path)


if __name__ == "__main__":
    logging.getLogger('pgosm-flex').info('Running PgOSM Flex!')
    run_pgosm_flex()
