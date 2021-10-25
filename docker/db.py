"""Interacts with Postgres
"""
import logging
import os
import sys
import subprocess

import psycopg
import sh


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
                            capture_output=True,
                            check=False)
    code = output.returncode
    if code == 3:
        err = 'Postgres check is misconfigured. Exiting.'
        logging.getLogger('pgosm-flex').error(err)
        sys.exit(err)
    return code == 0


def prepare_pgosm_db(data_only, paths):
    """Runs through series of steps to prepare database for PgOSM

    Parameters
    --------------------------
    data_only : bool
    paths : dict
    """
    pg_version_check()
    drop_pgosm_db()
    create_pgosm_db()
    if not data_only:
        LOGGER.info('Loading extras via Sqitch.')
        run_sqitch_prep(paths)
        load_qgis_styles(paths)
    else:
        LOGGER.info('Data only mode enabled, no Sqitch or QGIS styles.')


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

    LOGGER.debug('Setting Pg conn to enable autocommit - required for drop/create DB')
    conn.autocommit = True
    conn.execute(sql_raw)
    conn.close()
    LOGGER.info('Removed pgosm database')


def create_pgosm_db():
    """Creates the pgosm database and prepares with PostGIS and osm schema
    """
    sql_raw = 'CREATE DATABASE pgosm;'
    conn = get_db_conn(db_name='postgres')

    LOGGER.debug('Setting Pg conn to enable autocommit - required for drop/create DB')
    conn.autocommit = True
    conn.execute(sql_raw)
    conn.close()
    LOGGER.info('Created pgosm database')

    sql_create_postgis = "CREATE EXTENSION postgis;"
    sql_create_schema = "CREATE SCHEMA osm;"

    with get_db_conn(db_name='pgosm') as conn:
        cur = conn.cursor()
        cur.execute(sql_create_postgis)
        LOGGER.debug('Installed PostGIS extension')
        cur.execute(sql_create_schema)
        LOGGER.debug('Created osm schema')


def run_sqitch_prep(paths):
    """Runs Sqitch to create DB structure and populate helper data.

    Parameters
    -------------------------
    paths : dict

    Returns
    -------------------------
    success : bool
    """
    LOGGER.info('Deploy schema via Sqitch')

    conn_string = connection_string(db_name='pgosm')
    conn_string_sqitch = sqitch_db_string(db_name='pgosm')

    cmds_sqitch = ['sqitch', 'deploy', conn_string_sqitch]
    cmds_roads = ['psql', '-d', conn_string, '-f', 'data/roads-us.sql']
    output = subprocess.run(cmds_sqitch,
                            text=True,
                            capture_output=True,
                            cwd=paths['db_path'],
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
                            cwd=paths['db_path'],
                            check=False)
    if output.returncode > 0:
        LOGGER.error('Loading roads helper data failed. Check output')
        LOGGER.error(output.stderr)
        return False

    LOGGER.debug(f'Output from loading roads: {output.stdout}')
    LOGGER.info('Sqitch deployment complete')
    return True


def load_qgis_styles(paths):
    """Loads QGIS style data for easy formatting of most common layers.

    Parameters
    -------------------------
    paths : dict
    """
    LOGGER.info('Load QGIS styles...')
    # These two paths can easily be ran via psycopg
    create_path = os.path.join(paths['db_path'],
                               'qgis-style',
                               'create_layer_styles.sql')
    load_path = os.path.join(paths['db_path'],
                               'qgis-style',
                               '_load_layer_styles.sql')

    with open(create_path, 'r') as file_in:
        create_sql = file_in.read()

    with open(load_path, 'r') as file_in:
        load_sql = file_in.read()

    with get_db_conn(db_name='pgosm') as conn:
        cur = conn.cursor()
        cur.execute(create_sql)
    LOGGER.debug('QGIS Style table created')

    # Loading layer_styles data is done from files created by pg_dump, using
    # psql to reload is easiest
    conn_string = connection_string(db_name='pgosm')
    cmds_populate = ['psql', '-d', conn_string,
                     '-f', 'qgis-style/layer_styles.sql']

    output = subprocess.run(cmds_populate,
                            text=True,
                            capture_output=True,
                            cwd=paths['db_path'],
                            check=False)

    LOGGER.debug(f'Output from loading QGIS style data: {output.stdout}')

    with get_db_conn(db_name='pgosm') as conn:
        cur = conn.cursor()
        cur.execute(load_sql)
    LOGGER.info('QGIS Style table populated')

    with get_db_conn(db_name='pgosm') as conn:
        sql_clean = 'DELETE FROM public.layer_styles_staging;'
        cur = conn.cursor()
        cur.execute(sql_clean)
        LOGGER.debug('QGIS Style staging table cleaned')


def connection_string(db_name):
    """Returns connection string to pgosm database.

    Env vars for user/password defined by Postgres docker image.
    https://hub.docker.com/_/postgres/

    * POSTGRES_PASSWORD
    * POSTGRES_USER

    Parameters
    --------------------------
    db_name : str

    Returns
    --------------------------
    conn_string : str
    """
    app_str = '?application_name=pgosm-flex'

    pg_details = get_pg_user_pass()
    pg_user = pg_details['pg_user']
    pg_pass = pg_details['pg_pass']

    if pg_pass is None:
        conn_string = f'postgresql://{pg_user}@localhost/{db_name}{app_str}'
    else:
        conn_string = f'postgresql://{pg_user}:{pg_pass}@localhost/{db_name}{app_str}'

    return conn_string


def sqitch_db_string(db_name):
    """Returns DB string used for Sqitch.

    Parameters
    -----------------------
    db_name : str

    Returns
    -----------------------
    conn_string : str
    """
    pg_details = get_pg_user_pass()
    pg_user = pg_details['pg_user']
    pg_pass = pg_details['pg_pass']

    if pg_pass is None:
        conn_string = f'db:pg://{pg_user}@localhost/{db_name}'
    else:
        conn_string = f'db:pg://{pg_user}:{pg_pass}@localhost/{db_name}'

    return conn_string


def get_pg_user_pass():
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

    pg_details = {'pg_user': pg_user, 'pg_pass': pg_pass}
    return pg_details


def get_db_conn(db_name):
    """Establishes psycopg database connection.

    Parameters
    -----------------------
    db_name : str

    Returns
    -----------------------
    conn : psycopg.Connection
    """
    conn_string = connection_string(db_name)
    try:
        conn = psycopg.connect(conn_string)
        LOGGER.debug('Connection to Postgres established')
    except psycopg.OperationalError as err:
        err_msg = 'Database connection error. Error: {}'.format(err)
        LOGGER.error(err_msg)
        return False

    return conn


def pgosm_after_import(paths):
    """Runs post-processing SQL via Lua script.

    Layerset logic is established via environment variable, must happen
    before this step.

    Parameters
    ---------------------
    paths : dict
    """
    LOGGER.info('Running post-processing...')

    cmds = ['lua', 'run-sql.lua']

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
    sql_raw = 'CALL osm.build_nested_admin_polygons();'

    conn_string = connection_string(db_name='pgosm')
    cmds = ['psql', '-d', conn_string, '-c', sql_raw]
    LOGGER.info('Building nested polygons... (this can take a while)')
    output = subprocess.run(cmds,
                            text=True,
                            cwd=paths['flex_path'],
                            check=False,
                            stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    LOGGER.info(f'Nested polygon output: \n {output.stdout}')


    if output.returncode != 0:
        err_msg = f'Failed to build nested polygons. Return code: {output.returncode}'
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

    with get_db_conn(db_name='pgosm') as conn:
        cur = conn.cursor()
        cur.execute(sql_raw)


def run_pg_dump(export_filename, out_path, data_only, schema_name):
    """Runs pg_dump to save processed data to load into other PostGIS DBs.

    Parameters
    ---------------------------
    export_filename : str
    out_path : str
    data_only : bool
    schema_name : str
    """
    if not os.path.isabs(export_filename):
        export_path = os.path.join(out_path, export_filename)
    else:
        export_path = export_filename
    logger = logging.getLogger('pgosm-flex')
    db_name = 'pgosm'
    conn_string = connection_string(db_name=db_name)

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
    """
    result = sh.sed('-i',
           's/CREATE SCHEMA public;/CREATE SCHEMA IF NOT EXISTS public;/',
           export_path)
    LOGGER.debug('Completed replacement to not fail when public schema exists')
    LOGGER.debug(result)
