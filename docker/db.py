"""Interacts with Postgres
"""
import logging
import os
import subprocess

import psycopg2

LOGGER = logging.getLogger('pgosm-flex')


def pg_isready():
    """Checks pg_isready for Postgres to be available.

    https://www.postgresql.org/docs/current/app-pg-isready.html

    Returns
    -------------------
    pg_up : bool
    """
    output = subprocess.run(['pg_isready', '-U', 'root'],
                            text=True,
                            capture_output=True)
    code = output.returncode
    if code == 3:
        err = 'Postgres check is misconfigured. Exiting.'
        logging.getLogger('pgosm-flex').error(err)
        sys.exit(err)
    return code == 0


def prepare_pgosm_db():
    """Runs through series of steps to prepare database for PgOSM
    """
    pg_version_check()
    drop_pgosm_db()
    create_pgosm_db()
    LOGGER.warning('MISSING - Run sqitch deployment')
    LOGGER.warning('MISSING - Load QGIS styles')



def pg_version_check():
    """Checks Postgres version and sends to logs.
    """
    sql_raw = 'SHOW server_version;'

    with get_db_conn(db_name='postgres') as conn:
        cur = conn.cursor()
        cur.execute(sql_raw)
        results = cur.fetchone()

    pg_version = results[0]
    LOGGER.info(f'Postgres version {pg_version}')



def drop_pgosm_db():
    """Drops the pgosm database if it exists."""
    sql_raw = 'DROP DATABASE IF EXISTS pgosm;'

    conn = get_db_conn(db_name='postgres')
    cur = conn.cursor()
    # Required to drop DB
    conn.set_isolation_level(0)
    cur.execute(sql_raw)
    LOGGER.info('Removed pgosm database')


def create_pgosm_db():
    """Creates the pgosm database and prepares with PostGIS and osm schema
    """
    sql_raw = 'CREATE DATABASE pgosm;'

    conn = get_db_conn(db_name='postgres')
    cur = conn.cursor()
    # Required to drop DB
    conn.set_isolation_level(0)
    cur.execute(sql_raw)
    LOGGER.info('Created pgosm database')

    sql_create_postgis = "CREATE EXTENSION postgis;"
    sql_create_schema = "CREATE SCHEMA osm;"

    with get_db_conn(db_name='pgosm') as conn:
        cur = conn.cursor()
        cur.execute(sql_create_postgis)
        LOGGER.debug('Installed PostGIS extension')
        cur.execute(sql_create_schema)
        LOGGER.debug('Created osm schema')


def connection_string(db_name):
    """Returns connection string to pgosm database.

    Env vars for user/password defined by Postgres docker image.
    https://hub.docker.com/_/postgres/

    * POSTGRES_PASSWORD
    * POSTGRES_USER
    
    Returns
    --------------------------
    conn_string : str
    """
    app_str = '?application_name=pgosm-flex'
    try:
        pg_user = os.environ['POSTGRES_USER']
    except KeyError:
        LOGGER.debug('POSTGRES_USER not configured. Defaulting to postgres')
        pg_user = 'postgres'

    try:
        pg_pass = os.environ['POSTGRES_PASSWORD']
    except KeyError:
        LOGGER.debug('POSTGRES_PASSWORD not configured. Should work if ~/.pgpass is configured.')
        pg_pass = None

    if pg_pass is None:
        conn_string = f'postgresql://{pg_user}@localhost/{db_name}{app_str}'
    else:
        conn_string = f'postgresql://{pg_user}:{pg_pass}@localhost/{db_name}{app_str}'

    return conn_string


def get_db_conn(db_name):
    """Establishes psycopg database connection.
    """
    conn_string = connection_string(db_name)
    try:
        conn = psycopg2.connect(conn_string)
        LOGGER.debug('Connection to Postgres established')
    except psycopg2.OperationalError as err:
        err_msg = 'Database connection error.  Error: {}'.format(err)
        LOGGER.error(err_msg)
        return False
    return conn


def pgosm_after_import(layerset, paths):
    """Runs post-processing SQL via psql.

    Parameters
    ---------------------
    layerset : str

    paths : dict
    """
    LOGGER.info('Running post-processing...')
    conn_string = connection_string(db_name='pgosm')
    cmds = ['psql', '-d', conn_string, '-f', f'{layerset}.sql']
    output = subprocess.run(cmds,
                            text=True,
                            capture_output=True,
                            cwd=paths['flex_path'],
                            check=True)
    LOGGER.info(f'Post-processing output: \n {output.stderr}')


def pgosm_nested_admin_polygons(paths):
    """Runs stored procedure to calculate nested admin polygons via psql.

    Parameters
    ----------------------
    paths : dict
    """
    LOGGER.warning('MISSING - Make nested admin polygons optional!')
    sql_raw = 'CALL osm.build_nested_admin_polygons();'

    conn_string = connection_string(db_name='pgosm')
    cmds = ['psql', '-d', conn_string, '-c', sql_raw]
    LOGGER.info('Building nested polygons... (this can take a while)')
    output = subprocess.run(cmds,
                            text=True,
                            capture_output=True,
                            cwd=paths['flex_path'],
                            check=True)
    LOGGER.info(f'Nested polygon output: \n {output.stderr}')


def run_pg_dump(export_filename, out_path):
    export_path = os.path.join(out_path, export_filename)
    logger = logging.getLogger('pgosm-flex')
    db_name = 'pgosm'
    data_schema_name = 'osm'
    conn_string = connection_string(db_name=db_name)
    logger.info('Running pg_dump')
    cmds = ['pg_dump', '-d', conn_string,
            f'--schema={data_schema_name}',
            '-f', export_path]
    output = subprocess.run(cmds,
                            text=True,
                            capture_output=True,
                            check=False)
    LOGGER.info(f'pg_dump output: \n {output.stderr}')

