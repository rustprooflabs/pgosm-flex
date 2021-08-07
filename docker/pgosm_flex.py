#!/usr/bin/env python3
"""Python script to run PgOSM Flex.

Designed to be ran in Docker image:
    https://hub.docker.com/r/rustprooflabs/pgosm-flex
"""
import datetime
import logging
import os
from pathlib import Path
import shutil
import sys
import subprocess

import click
import time

import osm2pgsql_recommendation as rec
import db


BASE_PATH_DEFAULT = '/app'
"""Default path for pgosm-flex project for Docker.
"""

def get_today():
    today = datetime.datetime.today().strftime('%Y-%m-%d')
    return today

@click.command()
@click.option('--layerset', required=True,
              prompt='PgOSM Flex Layer Set',
              help='Layer set from PgOSM Flex to load. e.g. run-all')
@click.option('--ram', required=True,
              prompt='Server RAM (GB)',
              help='Amount of RAM in GB available on the server running this process.')
@click.option('--region', required=True,
              prompt="Region name",
              help='Region name matching the filename for data sourced from Geofabrik. e.g. north-america/us')
@click.option('--subregion', required=False,
              default=None,
              help='Sub-region name matching the filename for data sourced from Geofabrik. e.g. district-of-columbia')
@click.option('--pgosm-date', required=False,
              default=get_today(),
              envvar="PGOSM_DATE",
              help="Date of the data in YYYY-MM-DD format.")
@click.option('--basepath',
              required=False,
              default=BASE_PATH_DEFAULT,
              help='Used when testing locally and not within Docker')
@click.option('--skip-nested',
              default=False,
              envvar="PGOSM_SKIP_NESTED_POLYGON",
              is_flag=True,
              help='When True, skips calculating nested admin polygons. Can be time consuming on large regions.')
@click.option('--debug', is_flag=True)
def run_pgosm_flex(layerset, ram, region, subregion, pgosm_date,
                   basepath, debug, skip_nested):
    """Main logic to run PgOSM Flex within Docker.
    """
    paths = get_paths(base_path=basepath)
    log_file = get_log_path(region, subregion, paths)

    setup_logger(log_file, debug)
    logging.getLogger('pgosm-flex').info('PgOSM Flex starting...')
    pbf_file = prepare_data(region=region,
                            subregion=subregion,
                            pgosm_date=pgosm_date,
                            paths=paths)
    osm2pgsql_command = get_osm2pgsql_command(region=region,
                                              subregion=subregion,
                                              ram=ram,
                                              layerset=layerset,
                                              paths=paths)
    wait_for_postgres()

    db.prepare_pgosm_db()
    run_osm2pgsql(osm2pgsql_command=osm2pgsql_command, paths=paths)
    run_post_processing(layerset=layerset, paths=paths,
                        skip_nested=skip_nested)

    run_pg_dump()


def setup_logger(log_file, debug):
    """Prepares logging.

    Parameters
    ------------------------------
    log_file : str
        Path to log file

    debug : bool
        Enables debug mode when True.  INFO when False.
    """
    if debug:
        log_level = logging.DEBUG
    else:
        log_level = logging.INFO

    log_format = '%(asctime)s:%(levelname)s:%(name)s:%(module)s:%(message)s'
    logging.basicConfig(filename=log_file,
                        level=log_level,
                        filemode='w',
                        format=log_format)

    # Reduce verbosity of urllib3 logging
    logging.getLogger('urllib3').setLevel(logging.INFO)

    logger = logging.getLogger('pgosm-flex')
    logger.setLevel(log_level)
    handler = logging.FileHandler(filename=log_file)
    handler.setLevel(log_level)
    formatter = logging.Formatter(log_format)
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    logger.debug('Logger configured')


def get_log_path(region, subregion, paths):
    region_clean = region.replace('/', '-')
    if subregion == None:
        filename = f'{region_clean}.log'
    else:
        filename = f'{region_clean}-{subregion}.log'

    # Users will see this when they run, can copy/paste tail command.
    print(f'Log filename: {filename}')
    print('If running in Docker following procedures the file can be monitored')
    print(f'  tail -f pgosm-data/{filename}')
    log_file = os.path.join(paths['out_path'], filename)

    print(f'If testing locally:\n   tail -f {log_file}')
    return log_file


def get_paths(base_path):
    """Returns dictionary of various paths used.

    Creates `out_path` used for logs and data if necessary.

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

def get_region_filename(region, subregion):
    """Returns the filename needed to download/manage PBF files.

    Parameters
    ----------------------
    region : str
    subregion : str

    Returns
    ----------------------
    region_filename : str
    """
    base_name = '{}-latest.osm.pbf'
    if subregion == None:
        region_filename = base_name.format(region)
    else:
        region_filename = base_name.format(subregion)

    return region_filename


def get_pbf_url(region, subregion):
    """Returns the URL to the PBF for the region / subregion.

    Parameters
    ----------------------
    region : str
    subregion : str

    Returns
    ----------------------
    pbf_url : str
    """
    base_url = 'https://download.geofabrik.de'

    if subregion == None:
        pbf_url = f'{base_url}/{region}-latest.osm.pbf'
    else:
        pbf_url = f'{base_url}/{region}/{subregion}-latest.osm.pbf'

    return pbf_url


def wait_for_postgres():
    """Ensures Postgres service is reliably ready for use.

    Required b/c Postgres process in Docker gets restarted shortly
    after starting.
    """
    logger = logging.getLogger('pgosm-flex')
    logger.info('Checking for Postgres service to be available')

    required_checks = 2
    found = 0
    i = 0
    max_loops = 30

    while found < required_checks:
        if i > max_loops:
            err = 'Postgres still has not started. Exiting.'
            logger.error(err)
            sys.exit(err)

        time.sleep(5)

        if _check_pg_up():
            found += 1
            logger.info(f'Postgres up {found} times')

        if i % 5 == 0:
            logger.info('Waiting...')

        if i > 100:
            err = 'Postgres still not available. Exiting.'
            logger.error(err)
            sys.exit(err)
        i += 1

    logger.info('Database passed two checks - should be ready')


def _check_pg_up():
    """Checks pg_isready for Postgres to be available.

    https://www.postgresql.org/docs/current/app-pg-isready.html
    """
    output = subprocess.run(['pg_isready'], text=True, capture_output=True)
    code = output.returncode
    if code == 3:
        err = 'Postgres check is misconfigured. Exiting.'
        logging.getLogger('pgosm-flex').error(err)
        sys.exit(err)
    return code == 0


def prepare_data(region, subregion, pgosm_date, paths):
    """Ensures the PBF file is available.

    Checks if it already exists locally, download if needed,
    and verify MD5 checksum.

    Parameters
    ----------------------
    region : str
    subregion : str
    pgosm_date : str
    paths : dict

    Returns
    ----------------------
    pbf_file : str
        Full path to PBF file
    """
    out_path = paths['out_path']
    pbf_filename = get_region_filename(region, subregion)

    pbf_file = os.path.join(out_path, pbf_filename)
    pbf_file_with_date = pbf_file.replace('latest', pgosm_date)

    md5_file = f'{pbf_file}.md5'
    md5_file_with_date = f'{pbf_file_with_date}.md5'

    if pbf_download_needed(pbf_file_with_date, md5_file_with_date):
        logging.getLogger('pgosm-flex').info('Downloading PBF and MD5 files...')
        download_data(region, subregion, pbf_file, md5_file)
    else:
        logging.getLogger('pgosm-flex').warning('MISSING - Need to copy archived files to -latest filenames!')

    verify_checksum(md5_file, paths)

    archive_data(pbf_file, md5_file,
                 pbf_file_with_date, md5_file_with_date)

    return pbf_file


def pbf_download_needed(pbf_file_with_date, md5_file_with_date):
    """
    Returns
    --------------------------
    download_needed : bool
    """
    logger = logging.getLogger('pgosm-flex')
    # If the PBF file exists, check for the MD5 file too.
    if os.path.exists(pbf_file_with_date):
        logger.info(f'PBF File exists {pbf_file_with_date}')


        if os.path.exists(md5_file_with_date):
            logger.info('PBF & MD5 files exist.  Download not needed')
            download_needed = False
        else:
            if pgosm_date == get_today():
                print('PBF for today available but not MD5... download needed')
                download_needed = True
            else:
                err = 'Cannot validate historic PBF file. Exiting'
                logger.error(err)
                sys.exit(err)
    else:
        logger.info('PBF file not found locally. Download required')
        download_needed = True

    return download_needed

def download_data(region, subregion, pbf_file, md5_file):
    logger = logging.getLogger('pgosm-flex')
    logger.info(f'Downloading PBF data to {pbf_file}')
    pbf_url = get_pbf_url(region, subregion)

    result = subprocess.run(
        ['/usr/bin/wget', pbf_url,
         "-O", pbf_file , "--quiet"
        ],
        capture_output=True,
        text=True,
        check=True
    )

    logger.info(f'Downloading MD5 checksum to {md5_file}')
    result_md5 = subprocess.run(
        ['/usr/bin/wget', f'{pbf_url}.md5',
         "-O", md5_file , "--quiet"
        ],
        capture_output=True,
        text=True,
        check=True
    )


def verify_checksum(md5_file, paths):
    """If verfication fails, raises `CalledProcessError`
    """
    cmd = subprocess.run(['md5sum', '-c', md5_file],
                          capture_output=True,
                          text=True,
                          check=True,
                          cwd=paths['out_path'])
    return cmd


def archive_data(pbf_file, md5_file,
                 pbf_file_with_date, md5_file_with_date):
    if os.path.exists(pbf_file_with_date):
        pass # Do nothing
    else:
        shutil.copy2(pbf_file, pbf_file_with_date)

    if os.path.exists(md5_file_with_date):
        pass # Do nothing
    else:
        shutil.copy2(md5_file, md5_file_with_date)


def get_osm2pgsql_command(region, subregion, ram, layerset, paths):
    """Returns recommended osm2pgsql command.

    Parameters
    ----------------------
    region : str
    subregion : str
    ram : int
    layerset : str
    paths : dict

    Returns
    ----------------------
    rec_cmd : str
        osm2pgsql command recommended by the API
    """
    if subregion == None:
        region = region
    else:
        region = subregion

    pbf_filename = get_region_filename(region, subregion)
    rec_cmd = rec.osm2pgsql_recommendation(region=region,
                                           ram=ram,
                                           layerset=layerset,
                                           pbf_filename=pbf_filename,
                                           out_path=paths['out_path'])
    return rec_cmd


def run_osm2pgsql(osm2pgsql_command, paths):
    """Runs the provided osm2pgsql command.

    Parameters
    ----------------------
    osm2pgsql_command : str
    paths : dict
    """
    logger = logging.getLogger('pgosm-flex')
    logger.info(f'Running {osm2pgsql_command}')
    output = subprocess.run(osm2pgsql_command.split(),
                            text=True,
                            capture_output=True,
                            cwd=paths['flex_path'],
                            check=True)
    logger.info(f'osm2pgsql output: \n {output.stderr}\nEND osm2pgsql output')


def run_post_processing(layerset, paths, skip_nested):
    """Runs steps following osm2pgsql import.

    Post-processing SQL scripts and (optionally) calculate nested admin polgyons

    Parameters
    ----------------------
    layerset : str

    paths : dict

    skip_nested : bool
    """
    db.pgosm_after_import(layerset, paths)
    logger = logging.getLogger('pgosm-flex')
    if skip_nested:
        logger.info('Skipping calculating nested polygons')
    else:
        logger.info('Calculating nested polygons')
        db.pgosm_nested_admin_polygons(paths)


def run_pg_dump():
    logging.getLogger('pgosm-flex').warning('MISSING - run pg_dump')


if __name__ == "__main__":
    logging.getLogger('pgosm-flex').info('Running PgOSM Flex!')
    run_pgosm_flex()
