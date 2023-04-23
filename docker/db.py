"""Interacts with Postgres
"""
import logging
import os
import sys
import subprocess
import time
import psycopg
import sh

import qgis_styles

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
    pg_port = pg_details['pg_port']

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
        conn_string = f'postgresql://{pg_user}@{pg_host}:{pg_port}/{db_name}{app_str}'
    else:
        conn_string = f'postgresql://{pg_user}:{pg_pass}@{pg_host}:{pg_port}/{db_name}{app_str}'

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

    try:
        pg_port = os.environ['POSTGRES_PORT']
    except KeyError:
        pg_port = '5432'
        LOGGER.debug(f'POSTGRES_HOST not configured. Defaulting to {pg_port}')

    LOGGER.debug(f'PG Host: {pg_host} -- Port: {pg_port}')

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
                  'pg_port': pg_port,
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


def prepare_pgosm_db(skip_qgis_style, db_path, import_mode):
    """Runs through series of steps to prepare database for PgOSM.

    Parameters
    --------------------------
    skip_qgis_style : bool
    db_path : str
    import_mode : import_mode.ImportMode
    """
    if pg_conn_parts()['pg_host'] == 'localhost':
        drop_it = True
        LOGGER.debug('Running standard database prep for in-Docker operation. Includes DROP/CREATE DATABASE')
        LOGGER.debug(f'import_mode: {import_mode.as_json()}')
        if import_mode.slim_no_drop:
            if not import_mode.append_first_run:
                drop_it = False
            if import_mode.replication_update:
                drop_it = False

        if drop_it:
            LOGGER.debug('Dropping local database if exists')
            drop_pgosm_db()
        else:
            LOGGER.debug('Not dropping local DB. This is expected with subsequent import via --replication OR --update=append.')

        create_pgosm_db()

    else:
        LOGGER.info('Using external database. Ensure the target database is setup properly with proper permissions.')

    prepare_pgosm_schema()

    # Now always running sqitch. Moving more database structures into proper
    # management instead of being managed by Lua or Python.
    run_sqitch_prep(db_path)

    if skip_qgis_style:
        LOGGER.info('Skipping QGIS styles')
    else:
        LOGGER.info('Loading QGIS styles')
        qgis_styles.load_qgis_styles(db_path=db_path,
                                     db_name=pg_conn_parts()['pg_db'])
        


def start_import(pgosm_region, pgosm_date, srid, language, layerset, git_info,
                 osm2pgsql_version, import_mode):
    """Creates record in osm.pgosm_flex table.

    Parameters
    ---------------------------
    pgosm_region : str
    pgosm_date : str (ish?)
    srid : int
    language : str
    layerset : str
    git_info : str
    osm2pgsql_version : str
    import_mode : import_mode.ImportMode

    Returns
    ----------------------------
    import_id : int
        Value from the `id` column in `osm.pgosm_flex`.
    """
    params = {'pgosm_region': pgosm_region, 'pgosm_date': pgosm_date,
              'srid': srid, 'language': language, 'layerset': layerset,
              'git_info': git_info, 'osm2pgsql_version': osm2pgsql_version,
              'import_mode': import_mode.as_json()}

    sql_raw = """
INSERT INTO osm.pgosm_flex
    (osm_date, region, pgosm_flex_version, srid,
        osm2pgsql_version, "language", import_mode,
        layerset)
    VALUES(%(pgosm_date)s, %(pgosm_region)s, %(git_info)s, %(srid)s,
        %(osm2pgsql_version)s,
        COALESCE(%(language)s, ''), %(import_mode)s, %(layerset)s
        )
    RETURNING id
;
"""
    with get_db_conn(conn_string=os.environ['PGOSM_CONN']) as conn:
        cur = conn.cursor()
        cur.execute(sql_raw, params=params)
        import_id = cur.fetchone()[0]

    return import_id


def pg_version_check():
    """Checks Postgres machine-readable server_version_num.

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

    return True


def prepare_pgosm_schema():
    """Prepares the database with PostGIS and osm schema
    """
    sql_create_postgis = "CREATE EXTENSION IF NOT EXISTS postgis;"
    sql_create_schema = "CREATE SCHEMA IF NOT EXISTS osm;"

    with get_db_conn(conn_string=os.environ['PGOSM_CONN']) as conn:
        cur = conn.cursor()
        cur.execute(sql_create_postgis)
        LOGGER.debug('Installed PostGIS extension')
        cur.execute(sql_create_schema)
        LOGGER.debug('Created osm schema')


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
    LOGGER.info('Prep database to allow data updates.')
    # This use of append applies to both osm2pgsql --append and osm2pgsq-replication, not renaming from "append"
    sql_raw = 'CALL osm.append_data_start();'

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


def run_pg_dump(export_path, skip_qgis_style):
    """Runs pg_dump to save processed data to load into other PostGIS DBs.

    Parameters
    ---------------------------
    export_path : str
        Absolute path to output .sql file
    skip_qgis_style : bool
    """
    logger = logging.getLogger('pgosm-flex')
    conn_string = os.environ['PGOSM_CONN']
    schema_name = 'osm'

    if skip_qgis_style:
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


def log_import_message(import_id, msg):
    """Logs msg to database in osm.pgosm_flex for import_uuid.

    Parameters
    -------------------------------
    import_id : int
    msg : str
    """
    sql_raw = """
UPDATE osm.pgosm_flex
    SET import_status = %(msg)s
    WHERE id = %(import_id)s
;
"""
    with get_db_conn(conn_string=os.environ['PGOSM_CONN']) as conn:
        params = {'import_id': import_id, 'msg': msg}
        cur = conn.cursor()
        cur.execute(sql_raw, params=params)

