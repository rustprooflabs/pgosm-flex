"""Interacts with Postgres
"""
import logging
import os
import sys
import subprocess
import time
import psycopg
import sh


LOGGER = logging.getLogger('pgosm-flex')


def connection_string(admin=False):
    """Returns connection string to `db_name`.

    Env vars for user/password defined by Postgres docker image.
    https://hub.docker.com/_/postgres/

    * POSTGRES_PASSWORD
    * POSTGRES_USER
    * POSTGRES_HOST
    * POSTGRES_DB

    Parameters
    --------------------------
    admin : boolean
        Default False. Set to True to connect to admin database, currently
        hard-coded to `postgres`

    Returns
    --------------------------
    conn_string : str
    """
    app_str = '?application_name=pgosm-flex'

    pg_details = pg_conn_parts()
    pg_user = pg_details['pg_user']
    pg_pass = pg_details['pg_pass']
    pg_host = pg_details['pg_host']
    pg_db = pg_details['pg_db']

    if admin:
        if pg_host == 'localhost':
            db_name = 'postgres'
        else:
            # External databases only use admin connection for version check.
            # Can connect to main data DB for this, `postgres` db not required.
            # Should allow connection even when `postgres` database does not exist.
            db_name = pg_db
    else:
        db_name = pg_db

    if pg_pass is None:
        conn_string = f'postgresql://{pg_user}@{pg_host}/{db_name}{app_str}'
    else:
        conn_string = f'postgresql://{pg_user}:{pg_pass}@{pg_host}/{db_name}{app_str}'

    return conn_string


def pg_conn_parts():
    """Retrieves username/password from environment variables if they exist.

    Returns
    --------------------------
    pg_details : dict
    """
    try:
        pg_user = os.environ['POSTGRES_USER']
    except KeyError:
        LOGGER.debug('POSTGRES_USER not configured. Defaulting to postgres')
        pg_user = 'postgres'

    try:
        pg_pass = os.environ['POSTGRES_PASSWORD']
        if pg_pass == '':
            pg_pass = None
    except KeyError:
        LOGGER.debug('POSTGRES_PASSWORD not configured. Should work if ~/.pgpass is configured.')
        pg_pass = None

    try:
        pg_host = os.environ['POSTGRES_HOST']
    except KeyError:
        pg_host = 'localhost'
        LOGGER.debug(f'POSTGRES_HOST not configured. Defaulting to {pg_host}')

    LOGGER.debug(f'PG Host: {pg_host}')

    default_db = 'pgosm'
    pg_db = None

    try:
        pg_db = os.environ['POSTGRES_DB']
    except KeyError:
        LOGGER.debug(f'POSTGRES_DB not set.  Using default {default_db}')

    if pg_db is not None and pg_host == 'localhost':
        if pg_db != default_db:
            LOGGER.warning('POSTGRES_DB ignored when using in-Docker database.')
            pg_db = default_db

    if pg_db is None:
        pg_db = default_db

    LOGGER.debug(f'DB Name: {pg_db}')
    os.environ['POSTGRES_DB'] = pg_db

    pg_details = {'pg_user': pg_user,
                  'pg_pass': pg_pass,
                  'pg_host': pg_host,
                  'pg_db': pg_db}

    return pg_details


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
    sleep_s = 3

    while found < required_checks:
        if i > max_loops:
            err = 'Postgres still has not started. Exiting.'
            logger.error(err)
            sys.exit()

        time.sleep(sleep_s)

        if pg_isready():
            found += 1
            logger.debug(f'Postgres up {found} times')

        if i % 5 == 0:
            logger.debug('Waiting for Postgres connection...')

        i += 1

    logger.info('Postgres instance ready')


def pg_isready():
    """Checks for Postgres to be available.

    Uses pg_version_check() for simple approach.

    Returns
    -------------------
    pg_up : bool
    """
    try:
        result = pg_version_check()
    except AttributeError:
        err_msg = 'Error checking version, likely waiting for Postgres to start.'
        err_msg += ' Only an error if it does not go away after a few attempts.'
        logging.getLogger('pgosm-flex').warning(err_msg)
        return False

    if result is None:
        return False
    return True


def prepare_pgosm_db(data_only, db_path, append):
    """Runs through series of steps to prepare database for PgOSM.

    Parameters
    --------------------------
    data_only : bool
    db_path : str
    append : bool
    """

    if pg_conn_parts()['pg_host'] == 'localhost':
        LOGGER.debug('Running standard database prep for in-Docker operation. Includes DROP/CREATE DATABASE')
        if append:
            LOGGER.debug('Skipping DB drop b/c of append mode')
        else:
            LOGGER.debug('Dropping database')
            drop_pgosm_db()

        create_pgosm_db()
    else:
        LOGGER.info('Using external database. Ensure the target database is setup properly for PgOSM Flex with PostGIS, osm schema, and proper permissions.')

    if not data_only:
        LOGGER.info('Loading extras via Sqitch plus QGIS styles.')
        run_sqitch_prep(db_path)
        load_qgis_styles(db_path)
    else:
        LOGGER.info('Data only mode enabled, no Sqitch or QGIS styles.')


def pg_version_check():
    """Checks Postgres machine-readible server_version_num.

    Sends to logs and returns value.

    Results
    --------------------
    pg_version : int
    """
    sql_raw = """
SELECT setting
    FROM pg_catalog.pg_settings
    WHERE name = 'server_version_num'
;"""

    with get_db_conn(conn_string=os.environ['PGOSM_CONN_PG']) as conn:
        cur = conn.cursor()
        cur.execute(sql_raw)
        results = cur.fetchone()

    # It's an int https://www.postgresql.org/docs/current/runtime-config-preset.html#GUC-SERVER-VERSION-NUM
    pg_version = int(results[0])
    if pg_version < 120000:
        err_msg = f'Postgres version {pg_version} not supported. Postgres 12+ required.'
        LOGGER.error(err_msg)
        sys.exit(9)

    return pg_version


def drop_pgosm_db():
    """Drops the pgosm database if it exists.

    Intentionally hard coded to `pgosm` database for in-Docker use only.

    Returns
    ------------------------
    status : bool
    """
    if not pg_conn_parts()['pg_host'] == 'localhost':
        LOGGER.error('Attempted to drop database external from Docker. Not doing that')
        return False

    sql_raw = 'DROP DATABASE IF EXISTS pgosm;'
    conn = get_db_conn(conn_string=os.environ['PGOSM_CONN_PG'])

    LOGGER.debug('Setting Pg conn to enable autocommit - required for drop/create DB')
    conn.autocommit = True
    conn.execute(sql_raw)
    conn.close()
    LOGGER.info('Removed pgosm database')
    return True


def create_pgosm_db():
    """Creates the pgosm database and prepares with PostGIS and osm schema

    Intentionally hard coded to `pgosm` database for in-Docker use only.

    Returns
    -----------------------
    status : bool
    """
    if not pg_conn_parts()['pg_host'] == 'localhost':
        LOGGER.error('Attempted to create database external from Docker. Not doing that')
        return False

    sql_raw = 'CREATE DATABASE pgosm;'
    conn = get_db_conn(conn_string=os.environ['PGOSM_CONN_PG'])

    LOGGER.debug('Setting Pg conn to enable autocommit - required for drop/create DB')
    conn.autocommit = True
    try:
        conn.execute(sql_raw)
        LOGGER.info('Created pgosm database')
    except psycopg.errors.DuplicateDatabase:
        LOGGER.info('Database already existed.')
    finally:
        conn.close()

    sql_create_postgis = "CREATE EXTENSION IF NOT EXISTS postgis;"
    sql_create_schema = "CREATE SCHEMA IF NOT EXISTS osm;"

    with get_db_conn(conn_string=os.environ['PGOSM_CONN']) as conn:
        cur = conn.cursor()
        cur.execute(sql_create_postgis)
        LOGGER.debug('Installed PostGIS extension')
        cur.execute(sql_create_schema)
        LOGGER.debug('Created osm schema')

    return True


def run_sqitch_prep(db_path):
    """Runs Sqitch to create DB structure and populate helper data.

    Intentionally hard coded to `pgosm` database for in-Docker use only.

    Parameters
    -------------------------
    db_path : str

    Returns
    -------------------------
    success : bool
    """
    LOGGER.info('Deploy schema via Sqitch')

    conn_string = os.environ['PGOSM_CONN']
    conn_string_sqitch = sqitch_db_string()

    cmds_sqitch = ['sqitch', 'deploy', conn_string_sqitch]
    cmds_roads = ['psql', '-d', conn_string, '-f', 'data/roads-us.sql']
    output = subprocess.run(cmds_sqitch,
                            text=True,
                            capture_output=True,
                            cwd=db_path,
                            check=False)
    if output.returncode > 0:
        LOGGER.error('Loading Sqitch schema failed. pgosm schema will not be included in output.')
        LOGGER.error(output.stderr)
        return False

    LOGGER.debug(f'Output from Sqitch: {output.stdout}')
    LOGGER.info('Loading US Roads helper data')
    output = subprocess.run(cmds_roads,
                            text=True,
                            capture_output=True,
                            cwd=db_path,
                            check=False)
    if output.returncode > 0:
        LOGGER.error('Loading roads helper data failed. Check output')
        LOGGER.error(output.stderr)
        return False

    LOGGER.debug(f'Output from loading roads: {output.stdout}')
    LOGGER.info('Sqitch deployment complete')
    return True


def load_qgis_styles(db_path):
    """Loads QGIS style data for easy formatting of most common layers.

    Parameters
    -------------------------
    db_path : str
    """
    LOGGER.info('Load QGIS styles...')
    # These two paths can easily be ran via psycopg
    create_path = os.path.join(db_path,
                               'qgis-style',
                               'create_layer_styles.sql')
    load_path = os.path.join(db_path,
                             'qgis-style',
                             '_load_layer_styles.sql')

    with open(create_path, 'r') as file_in:
        create_sql = file_in.read()

    with open(load_path, 'r') as file_in:
        load_sql = file_in.read()

    with get_db_conn(conn_string=os.environ['PGOSM_CONN']) as conn:
        cur = conn.cursor()
        cur.execute(create_sql)
    LOGGER.debug('QGIS Style table created')

    # Loading layer_styles data is done from files created by pg_dump, using
    # psql to reload is easiest
    conn_string = os.environ['PGOSM_CONN']
    cmds_populate = ['psql', '-d', conn_string,
                     '-f', 'qgis-style/layer_styles.sql']

    output = subprocess.run(cmds_populate,
                            text=True,
                            capture_output=True,
                            cwd=db_path,
                            check=False)

    LOGGER.debug(f'Output from loading QGIS style data: {output.stdout}')

    with get_db_conn(conn_string=os.environ['PGOSM_CONN']) as conn:
        cur = conn.cursor()
        cur.execute(load_sql)
    LOGGER.info('QGIS Style table populated')

    with get_db_conn(conn_string=os.environ['PGOSM_CONN']) as conn:
        sql_clean = 'DELETE FROM public.layer_styles_staging;'
        cur = conn.cursor()
        cur.execute(sql_clean)
        LOGGER.debug('QGIS Style staging table cleaned')


def sqitch_db_string():
    """Returns DB string used for Sqitch.

    Returns
    -----------------------
    conn_string : str
    """
    conn_string = f'db:{connection_string()}'
    return conn_string


def get_db_conn(conn_string):
    """Establishes psycopg database connection.

    Parameters
    -----------------------
    conn_string : str

    Returns
    -----------------------
    conn : psycopg.Connection
    """
    try:
        conn = psycopg.connect(conn_string)
        LOGGER.debug('Connection to Postgres established')
    except psycopg.OperationalError as err:
        err_msg = 'Database connection error. Error: {}'.format(err)
        LOGGER.error(err_msg)
        return False

    return conn


def pgosm_after_import(flex_path):
    """Runs post-processing SQL via Lua script.

    Layerset logic is established via environment variable, must happen
    before this step.

    Parameters
    ---------------------
    flex_path : str
    """
    LOGGER.info('Running post-processing...')

    cmds = ['lua', 'run-sql.lua']

    output = subprocess.run(cmds,
                            text=True,
                            cwd=flex_path,
                            check=False,
                            stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    LOGGER.info(f'Post-processing SQL output: \n {output.stdout}')

    if output.returncode != 0:
        err_msg = f'Failed to run post-processing SQL. Return code: {output.returncode}'
        LOGGER.error(err_msg)
        return False

    return True


def pgosm_nested_admin_polygons(flex_path):
    """Runs stored procedure to calculate nested admin polygons via psql.

    Parameters
    ----------------------
    flex_path : str
    """
    sql_raw = 'CALL osm.build_nested_admin_polygons();'

    conn_string = os.environ['PGOSM_CONN']
    cmds = ['psql', '-d', conn_string, '-c', sql_raw]
    LOGGER.info('Building nested polygons... (this can take a while)')
    output = subprocess.run(cmds,
                            text=True,
                            cwd=flex_path,
                            check=False,
                            stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    LOGGER.info(f'Nested polygon output: \n {output.stdout}')

    if output.returncode != 0:
        err_msg = f'Failed to build nested polygons. Return code: {output.returncode}'
        LOGGER.error(err_msg)
        sys.exit(f'{err_msg} - Check the log output for details.')



def osm2pgsql_replication_start():
    """Runs pre-replication step to clean out FKs that would prevent updates.
    """
    LOGGER.error('Not running cleanup step in SQL yet!')
    sql_raw = 'CALL osm.append_data_start   ();'

    with get_db_conn(conn_string=connection_string()) as conn:
        cur = conn.cursor()
        cur.execute(sql_raw)


def osm2pgsql_replication_finish(skip_nested):
    """Runs post-replication step to put FKs back and refresh materialied views.

    Parameters
    ---------------------
    skip_nested : bool
    """
    # Fails via psycopg, using psql
    if skip_nested:
        LOGGER.info('Finishing Replication, skipping nested polygons')
        sql_raw = 'CALL osm.append_data_finish(skip_nested := True );'
    else:
        LOGGER.info('Finishing Replication, including nested polygons')
        sql_raw = 'CALL osm.append_data_finish(skip_nested := False );'

    conn_string = os.environ['PGOSM_CONN']
    cmds = ['psql', '-d', conn_string, '-c', sql_raw]
    LOGGER.info('Finishing Replication')
    output = subprocess.run(cmds,
                            text=True,
                            check=False,
                            stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    LOGGER.info(f'Finishing replication output: \n {output.stdout}')

    if output.returncode != 0:
        err_msg = f'Failed to finish replication. Return code: {output.returncode}'
        LOGGER.error(err_msg)
        sys.exit(f'{err_msg} - Check the log output for details.')


def rename_schema(schema_name):
    """Renames default schema name "osm" to `schema_name`

    Returns
    ----------------------------
    schema_name : str
    """
    LOGGER.info(f'Renaming schema from osm to {schema_name}')
    sql_raw = f'ALTER SCHEMA osm RENAME TO {schema_name} ;'

    with get_db_conn(conn_string=os.environ['PGOSM_CONN']) as conn:
        cur = conn.cursor()
        cur.execute(sql_raw)


def run_pg_dump(export_path, data_only, schema_name):
    """Runs pg_dump to save processed data to load into other PostGIS DBs.

    Parameters
    ---------------------------
    export_path : str
        Absolute path to output .sql file
    data_only : bool
    schema_name : str
    """
    logger = logging.getLogger('pgosm-flex')
    db_name = os.environ['POSTGRES_DB']
    conn_string = os.environ['PGOSM_CONN']

    if data_only:
        logger.info(f'Running pg_dump (only {schema_name} schema)')
        cmds = ['pg_dump', '-d', conn_string,
                f'--schema={schema_name}',
                '-f', export_path]
    else:
        logger.info(f'Running pg_dump ({schema_name} schema plus extras)')
        cmds = ['pg_dump', '-d', conn_string,
                f'--schema={schema_name}',
                '--schema=pgosm',
                '--schema=public',
                '-f', export_path]

    output = subprocess.run(cmds,
                            text=True,
                            capture_output=True,
                            check=False)
    LOGGER.info(f'pg_dump complete, saved to {export_path}')
    LOGGER.debug(f'pg_dump output: \n {output.stderr}')
    fix_pg_dump_create_public(export_path)


def fix_pg_dump_create_public(export_path):
    """Using pg_dump with `--schema=public` results in
    a .sql script containing `CREATE SCHEMA public;`, nearly always breaks
    in target DB.  Replaces with `CREATE SCHEMA IF NOT EXISTS public;`

    Parameters
    ----------------------
    export_path : str
    """
    result = sh.sed('-i',
           's/CREATE SCHEMA public;/CREATE SCHEMA IF NOT EXISTS public;/',
           export_path)
    LOGGER.debug('Completed replacement to not fail when public schema exists')
    LOGGER.debug(result)
