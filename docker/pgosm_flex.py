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
def run_pgosm_flex(layerset, ram, region, subregion, pgosm_date,
                   basepath):
    """Main logic to run PgOSM Flex within Docker.
    """
    paths = get_paths(base_path=basepath)
    log_file = get_log_path(region, subregion, paths)
    print(f'Logging output to {log_file}')

    logging.basicConfig(filename=log_file,
                        level=logging.DEBUG,
                        format=f'%(asctime)s %(levelname)s %(name)s %(threadName)s : %(message)s')
    logging.getLogger('urllib3').setLevel(logging.INFO)

    logging.info('PgOSM Flex starting...')

    pbf_file = prepare_data(region=region,
                            subregion=subregion,
                            pgosm_date=pgosm_date,
                            paths=paths)
    osm2pgsql_command = get_osm2pgsql_command(region=region,
                                              subregion=subregion,
                                              ram=ram,
                                              layerset=layerset,
                                              pbf_file=pbf_file,
                                              paths=paths)
    wait_for_postgres()

    prepare_pgosm_db()
    run_osm2pgsql(osm2pgsql_command=osm2pgsql_command)
    run_post_processing()

    run_pg_dump()


def get_log_path(region, subregion, paths):
    region_clean = region.replace('/', '-')
    if subregion == None:
        filename = f'{region_clean}.log'
    else:
        filename = f'{region_clean}-{subregion}.log'

    log_file = os.path.join(paths['out_path'], filename)
    return log_file


def get_paths(base_path):
    """Returns dictionary of various paths used.

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
    logging.info('Checking for Postgres service to be available')

    required_checks = 2
    found = 0
    i = 0
    max_loops = 30

    while found < required_checks:
        if i > max_loops:
            err = 'Postgres still has not started. Exiting.'
            logging.error(err)
            sys.exit(err)

        time.sleep(5)

        if _check_pg_up():
            found += 1
            logging.info(f'Postgres up {found} times')

        if i % 5 == 0:
            logging.info('Waiting...')

        if i > 100:
            err = 'Postgres still not available. Exiting.'
            logging.error(err)
            sys.exit(err)
        i += 1

    logging.info('Database passed two checks - should be ready')


def _check_pg_up():
    """Checks pg_isready for Postgres to be available.

    https://www.postgresql.org/docs/current/app-pg-isready.html
    """
    output = subprocess.run(['pg_isready'], text=True, capture_output=True)
    code = output.returncode
    if code == 3:
        err = 'Postgres check is misconfigured. Exiting.'
        logging.error(err)
        sys.exit(err)
    return code == 0


def prepare_data(region, subregion, pgosm_date, paths):
    out_path = paths['out_path']
    pbf_filename = get_region_filename(region, subregion)

    pbf_file = os.path.join(out_path, pbf_filename)
    # create oputput folder if not already there
    Path(out_path).mkdir(parents=True, exist_ok=True)
    pbf_file_with_date = pbf_file.replace('latest', pgosm_date)

    md5_file = f'{pbf_file}.md5'
    md5_file_with_date = f'{pbf_file_with_date}.md5'

    if pbf_download_needed(pbf_file_with_date, md5_file_with_date):
        logging.info('Downloading PBF and MD5 files...')
        download_data(region, subregion, pbf_file, md5_file)
    else:
        logging.warning('MISSING - Need to copy archived files to -latest filenames!')

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
    # If the PBF file exists, check for the MD5 file too.
    if os.path.exists(pbf_file_with_date):
        logging.info(f'PBF File exists {pbf_file_with_date}')


        if os.path.exists(md5_file_with_date):
            logging.info('PBF & MD5 files exist.  Download not needed')
            download_needed = False
        else:
            if pgosm_date == get_today():
                print('PBF for today available but not MD5... download needed')
                download_needed = True
            else:
                err = 'Cannot validate historic PBF file. Exiting'
                logging.error(err)
                sys.exit(err)
    else:
        logging.info('PBF file not found locally. Download required')
        download_needed = True

    return download_needed

def download_data(region, subregion, pbf_file, md5_file):
    # Download if Not
    logging.info(f'Downloading PBF data to {pbf_file}')
    pbf_url = get_pbf_url(region, subregion)

    result = subprocess.run(
        ['/usr/bin/wget', pbf_url,
         "-O", pbf_file , "--quiet"
        ],
        capture_output=True,
        text=True,
        check=True
    )

    logging.info(f'Downloading MD5 checksum to {md5_file}')
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


def get_osm2pgsql_command(region, subregion, ram, layerset, pbf_file, paths):
    """Returns recommended osm2pgsql command.

    Parameters
    ----------------------
    region : str
    subregion : str
    ram : int
    layerset : str
    pbf_file : str
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

    rec_cmd = rec.osm2pgsql_recommendation(region=region,
                                           ram=ram,
                                           layerset=layerset,
                                           pbf_filename=pbf_file,
                                           out_path=paths['out_path'])
    return rec_cmd


def prepare_pgosm_db():
    drop_pgosm_db()
    create_pgosm_db()
    logging.warning('Run sqitch deployment')
    logging.warning('Load QGIS styles')


def drop_pgosm_db():
    # Drop if exists
    logging.warning('Need to drop/create db')

def create_pgosm_db():
    logging.warning('Install PostGIS, Create osm schema')


def run_osm2pgsql(osm2pgsql_command):
    logging.warning(f'Need to run {osm2pgsql_command}')


def run_post_processing():
    logging.warning('Need to run post-processing SQL')


def run_pg_dump():
    logging.warning('FIXME: run pg_dump')


if __name__ == "__main__":
    logging.info('Running PgOSM Flex!')
    run_pgosm_flex()
