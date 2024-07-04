"""Generic functions and attributes used in multiple modules of PgOSM Flex.
"""
import datetime
import json
import logging
from packaging.version import parse as parse_version
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


def get_git_info(tag_only: bool=False) -> str:
    """Provides git info in the form of the latest tag and most recent short sha

    Sends info to logger and returns string.

    Parameters
    ----------------------
    tag_only : bool
        When true, omits the short sha portion, only returning the tag.

    Returns
    ----------------------
    git_info : str
    """
    logger = logging.getLogger('pgosm-flex')

    try:
        repo = git.Repo()
    except git.exc.InvalidGitRepositoryError:
        # This error happens when running via make for some reason...
        # This appears to fix it.
        repo = git.Repo('../')

    try:
        sha = repo.head.object.hexsha
        short_sha = repo.git.rev_parse(sha, short=True)
        latest_tag = repo.git.describe('--abbrev=0', tags=True)
    except ValueError:
        git_info = 'Git info unavailable'
        logger.error('Unable to get git information.')
        return '-- (version unknown) --'

    if tag_only:
        git_info = latest_tag
    else:
        git_info = f'{latest_tag}-{short_sha}'
        # Logging only this full version, not the tag_only run
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


class ImportMode():
    """Determines logical variables used to control program flow.

    WARNING:  The values for `append_first_run` and `replication_update`
    are used to determine when to drop the local DB.  Be careful with any
    changes to these values.
    """
    def __init__(self, replication: bool, replication_update: bool,
                 update: str, force: bool):
        """Computes two variables, slim_no_drop and append_first_run
        based on inputs.

        Parameters
        --------------------------
        replication : bool
        replication_update : bool
        update : str or None
            Valid options are 'create' or 'append', lining up with osm2pgsql's
            `--create` and `--append` modes.
        force : bool
        """
        self.logger = logging.getLogger('pgosm-flex')
        self.replication = replication
        self.replication_update = replication_update

        # The input via click should enforce this, still worth checking here
        valid_update_options = ['append', 'create', None]

        if update not in valid_update_options:
            raise ValueError(f'Invalid option for --update. Valid options: {valid_update_options}')

        self.update = update
        self.force = force

        self.set_slim_no_drop()
        self.set_append_first_run()
        self.set_run_post_sql()


    def okay_to_run(self, prior_import: dict) -> bool:
        """Determines if it is okay to run PgOSM Flex without fear of data loss.

        This logic was along with the `--force` option to make it
        less likely to accidentally lose data with improper PgOSM Flex
        options.

        Remember, this is free and open source software and there is
        no warranty!
        This does not imply a guarantee that you **cannot** lose data,
        only that we want to make it **less likely** something bad will happen.
        If you find a way bad things can happen that could be detected here,
        please open an issue:

            https://github.com/rustprooflabs/pgosm-flex/issues/new?assignees=&labels=&projects=&template=bug_report.md&title=Data%20Safety%20Idea

        Parameters
        -------------------
        prior_import : dict
            Details about the latest import from osm.pgosm_flex table.

            An empty dictionary (len==0) indicates no prior import.
            Only the replication key is specifically used

        Returns
        -------------------
        okay_to_run : bool
        """
        self.logger.debug(f'Checking if it is okay to run...')
        if self.force:
            self.logger.warn(f'Using --force, kiss existing data goodbye')
            return True

        # If no prior imports, do not require force
        if len(prior_import) == 0:
            self.logger.debug(f'No prior import found, okay to proceed.')
            return True

        prior_replication = prior_import['replication']

        # Check git version against latest.
        # If current version is lower than prior version from latest import, stop.
        prior_import_version = prior_import['pgosm_flex_version_no_hash']
        git_tag = get_git_info(tag_only=True)

        if git_tag == '-- (version unknown) --':
            msg = 'Unable to detect PgOSM Flex version from Git.'
            msg += ' Not enforcing version check against prior version.'
            self.logger.warning(msg)
        elif parse_version(git_tag) < parse_version(prior_import_version):
            msg = f'PgOSM Flex version ({git_tag}) is lower than latest import'
            msg += f' tracked in the pgosm_flex table ({prior_import_version}).'
            msg += f' Use PgOSM Flex version {prior_import_version} or newer'
            self.logger.error(msg)
            return False
        else:
            self.logger.info(f'Prior import used PgOSM Flex: {prior_import_version}')

        if self.replication:
            if not prior_replication:
                self.logger.error('Running w/ replication but prior import did not.  Requires --force to proceed.')
                return False
            self.logger.debug('Okay to proceed with replication')
            return True

        msg = 'Prior data exists in the osm schema and --force was not used.'
        self.logger.error(msg)
        return False

    def set_append_first_run(self):
        """Uses `replication_update` and `update` to determine value for
        `self.append_first_run`
        """
        if self.replication_update:
            self.append_first_run = False
        else:
            self.append_first_run = True

        if self.update is not None:
            if self.update == 'create':
                self.append_first_run = True
            else:
                self.append_first_run = False

    def set_slim_no_drop(self):
        """Uses `replication` and `update` to determine value for
        `self.slim_no_drop`
        """
        self.slim_no_drop = False

        if self.replication:
            self.slim_no_drop = True

        if self.update is not None:
            self.slim_no_drop = True

    def set_run_post_sql(self):
        """Uses `update` value to determine value for
        `self.run_post_sql`.  This value determines if the post-processing SQL
        should be executed.

        Note:  Not checking replication/replication_update because subsequent
        imports use osm2pgsql-replication, which does not attempt to run
        the post-processing SQL scripts.
        """
        self.run_post_sql = True

        if self.update is not None:
            if self.update == 'append':
                self.run_post_sql = False

    def as_json(self) -> str:
        """Packs key details as a dictionary passed through `json.dumps()`

        Returns
        ------------------------
        json_text : str
            Text representation of JSON object built using class attributes.
        """
        self_as_dict = {'update': self.update,
                'replication': self.replication,
                'replication_update': self.replication_update,
                'append_first_run': self.append_first_run,
                'slim_no_drop': self.slim_no_drop,
                'run_post_sql': self.run_post_sql}
        return json.dumps(self_as_dict)


