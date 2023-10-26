"""Generic functions and attributes used in multiple modules of PgOSM Flex.
"""
import datetime
import logging
import subprocess
import os
import sys
from time import sleep
import git

import db


DEFAULT_SRID = '3857'


def get_today() -> str:
    """Returns yyyy-mm-dd formatted string for today.

    Returns
    -------------------------
    today : str
    """
    today = datetime.datetime.today().strftime('%Y-%m-%d')
    return today


def run_command_via_subprocess(cmd: list, cwd: str, output_lines: list=[],
                               print: bool=False) -> int:
    """Wraps around subprocess.Popen() to run commands outside of Python. Prints
    output as it goes, returns the status code from the command.

    Parameters
    -----------------------
    cmd : list
        Parts of the command to run.
    cwd : str or None
        Set the working directory, or to None.
    output_lines : list
        Pass in a list to return the output details.
    print : bool
        Default False.  Set to true to also print to logger

    Returns
    -----------------------
    status : int
        Return code from command
    """
    logger = logging.getLogger('pgosm-flex')
    with subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT
                          ) as process:
        while True:
            output = process.stdout.readline()
            if process.poll() is not None and output == b'':
                break

            if output:
                ln = output.strip().decode('utf-8')
                output_lines.append(ln)
                if print:
                    logger.info(ln)
            else:
                # Only sleep when there wasn't output
                sleep(1)
        status = process.poll()
    return status


def verify_checksum(md5_file: str, path: str):
    """Verifies checksum of osm pbf file.

    If verification fails calls `sys.exit()`

    Parameters
    ---------------------
    md5_file : str
        Filename of the MD5 file to verify the osm.pbf file.
    path : str
        Path to directory with `md5_file` to validate
    """
    logger = logging.getLogger('pgosm-flex')
    logger.debug(f'Validating {md5_file} in {path}')

    returncode = run_command_via_subprocess(cmd=['md5sum', '-c', md5_file],
                                            cwd=path)

    if returncode != 0:
        err_msg = f'Failed to validate md5sum. Return code: {returncode}'
        logger.error(err_msg)
        sys.exit(err_msg)

    logger.debug('md5sum validated')


def set_env_vars(region, subregion, srid, language, pgosm_date, layerset,
                 layerset_path, replication, schema_name):
    """Sets environment variables needed by PgOSM Flex. Also creates DB
    record in `osm.pgosm_flex` table.

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
    replication : bool
        Indicates when osm2pgsql-replication is used
    schema_name : str
    """
    logger = logging.getLogger('pgosm-flex')
    logger.debug('Ensuring env vars are not set from prior run')
    unset_env_vars()
    logger.debug('Setting environment variables')

    os.environ['PGOSM_REGION'] = region


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
    os.environ['SCHEMA_NAME'] = schema_name

    # PGOSM_CONN is required to be set by the Lua styles used by osm2pgsql
    os.environ['PGOSM_CONN'] = db.connection_string()
    # Connection to DB for admin purposes, e.g. drop/create main database
    os.environ['PGOSM_CONN_PG'] = db.connection_string(admin=True)

    pgosm_region = get_region_combined(region, subregion)
    logger.debug(f'PGOSM_REGION_COMBINED: {pgosm_region}')



def get_region_combined(region: str, subregion: str) -> str:
    """Returns combined region with optional subregion.

    Parameters
    ------------------------
    region : str
    subregion : str (or None)

    Returns
    -------------------------
    pgosm_region : str
    """
    if subregion is None:
        pgosm_region = f'{region}'
    else:
        os.environ['PGOSM_SUBREGION'] = subregion
        pgosm_region = f'{region}-{subregion}'

    return pgosm_region


def get_git_info() -> str:
    """Provides git info in the form of the latest tag and most recent short sha

    Sends info to logger and returns string.

    Returns
    ----------------------
    git_info : str
    """
    logger = logging.getLogger('pgosm-flex')
    repo = git.Repo()
    try:
        sha = repo.head.object.hexsha
        short_sha = repo.git.rev_parse(sha, short=True)
        latest_tag = repo.git.describe('--abbrev=0', tags=True)
        git_info = f'{latest_tag}-{short_sha}'
    except ValueError:
        git_info = 'Git info unavailable'
        logger.error('Unable to get git information.')

    logger.info(f'PgOSM Flex version:  {git_info}')
    return git_info


def unset_env_vars():
    """Unsets environment variables used by PgOSM Flex.

    Does not pop POSTGRES_DB on purpose to allow non-Docker operation.
    """
    os.environ.pop('PGOSM_REGION', None)
    os.environ.pop('PGOSM_SUBREGION', None)
    os.environ.pop('PGOSM_SRID', None)
    os.environ.pop('PGOSM_LANGUAGE', None)
    os.environ.pop('PGOSM_LAYERSET_PATH', None)
    os.environ.pop('PGOSM_DATE', None)
    os.environ.pop('PGOSM_LAYERSET', None)
    os.environ.pop('PGOSM_CONN', None)
    os.environ.pop('PGOSM_CONN_PG', None)
    os.environ.pop('SCHEMA_NAME', None)
