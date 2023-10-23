"""Module to interact with Postgres database.
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


def connection_string(admin: bool=False, pgbouncer: bool=False,
                      pgbouncer_admin: bool=False) -> str:
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

    pgbouncer : boolean
        Default False.
        FIXME:  SET DEFAULT TO TRUE???

    pgbouncer_admin : boolean
        Default False
        Connects to pgbouncer database (must be pgbouncer connection) for admin
        functionality, e.g. `SHUTDOWN;`

    Returns
    --------------------------
    conn_string : str
    """
    app_str = '?application_name=pgosm-flex'

    pg_details = pg_conn_parts()
    pg_user = pg_details['pg_user']
    pg_pass = pg_details['pg_pass']

    pg_db = pg_details['pg_db']

    if pgbouncer_admin and not pgbouncer:
        raise ValueError('Cannot connect to pgbouncer_admin on non-pgbouncer connection.')

    if pgbouncer:
        pg_host = pg_details['pg_host_pgbouncer']
        pg_port = pg_details['pg_port_pgbouncer']
    else:
        pg_host = pg_details['pg_host']
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

    # Just overwriting instead of working into above logic.  Probably a good
    # sign this logic should be improved...
    if pgbouncer_admin:
        db_name = 'pgbouncer'

    if pg_pass is None:
        conn_string = f'postgresql://{pg_user}@{pg_host}:{pg_port}/{db_name}{app_str}'
    else:
        conn_string = f'postgresql://{pg_user}:{pg_pass}@{pg_host}:{pg_port}/{db_name}{app_str}'

    return conn_string


def get_db_conn_string() -> str:
    """Returns non-admin database connection, either pgBouncer or not depending
    on run-time configuration.

    Returns
    ----------------------------
    conn_string : str
    """
    if os.environ['USE_PGBOUNCER'] == 'true':
        LOGGER.debug('Using pgBouncer connection string')
        conn_string = os.environ['PGOSM_CONN_PGBOUNCER']
    else:
        LOGGER.debug('Using direct to Postgres connection string (non-admin)')
        conn_string = os.environ['PGOSM_CONN']

    return conn_string


def pg_conn_parts() -> dict:
    """Returns dictionary of connection parts based on environment variables
    if they exist.

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
                  'pg_db': pg_db,
                  'pg_host_pgbouncer': 'localhost',
                  'pg_port_pgbouncer': 6432
                  }

    return pg_details


def wait_for_postgres():
    """Ensures Postgres service is reliably ready for use.

    Required b/c Postgres process in Docker gets restarted shortly
    after starting.  Calls `sys.exit()` after `max_loops` reached
    indicating failure due to inability to connect.
    """
    logger = logging.getLogger('pgosm-flex')
    logger.info('Checking for Postgres service to be available')
    log_pg_details()

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


def pg_isready() -> bool:
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


def log_pg_details():
    """Logs non-sensitive Postgres connection details to LOGGER.
    """
    conn_parts = pg_conn_parts()
    pg_host = conn_parts['pg_host']
    pg_port = conn_parts['pg_port']
    db_name = conn_parts['pg_db']
    pg_user = conn_parts['pg_user']
    msg = f'Connecting to Postgres using role "{pg_user}" on host '
    msg += f' "{pg_host}:{pg_port}"'
    msg += f'  in database "{db_name}"'
    LOGGER.info(msg)


def prepare_pgosm_db(skip_qgis_style, db_path, import_mode, schema_name):
    """Runs through series of steps to prepare database for PgOSM.

    Parameters
    --------------------------
    skip_qgis_style : bool
    db_path : str
    import_mode : import_mode.ImportMode
    schema_name : str
        Schema name for OpenStreetMap data
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

    prepare_osm_schema(db_path=db_path, skip_qgis_style=skip_qgis_style,
                       schema_name=schema_name)
    run_insert_pgosm_road(db_path=db_path, schema_name=schema_name)


def start_import(pgosm_region, pgosm_date, srid, language, layerset, git_info,
                 osm2pgsql_version, import_mode, schema_name, input_file):
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
    schema_name : str
    input_file : str

    Returns
    ----------------------------
    import_id : int
        Value from the `id` column in `osm.pgosm_flex`.
    """
    params = {'pgosm_region': pgosm_region, 'pgosm_date': pgosm_date,
              'srid': srid, 'language': language, 'layerset': layerset,
              'git_info': git_info, 'osm2pgsql_version': osm2pgsql_version,
              'import_mode': import_mode.as_json(),
              'input_file': input_file}

    sql_raw = """
INSERT INTO {schema_name}.pgosm_flex
    (osm_date, region, pgosm_flex_version, srid,
        osm2pgsql_version, "language", import_mode,
        layerset, input_file)
    VALUES(%(pgosm_date)s, %(pgosm_region)s, %(git_info)s, %(srid)s,
        %(osm2pgsql_version)s,
        COALESCE(%(language)s, ''), %(import_mode)s, %(layerset)s,
        %(input_file)s
        )
    RETURNING id
;
"""
    sql_raw = sql_raw.format(schema_name=schema_name)
    with get_db_conn(conn_string=get_db_conn_string()) as conn:
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


def prepare_osm_schema(db_path: str, skip_qgis_style: bool, schema_name: str):
    """Runs deploy scripts to prepare the PgOSM Flex database.

    This function's code could be simplified, but currently I like the verbosity
    of it. It doesn't need to stay like this forever, but for now... it's fine.

    Parameters
    ---------------------------
    db_path : str
        Path to folder with SQL scripts.
    skip_qgis_style : bool
    scheme_name : str
    """
    LOGGER.info(f'Preparing database schema: {schema_name}')
    create_osm_file = 'osm.sql'
    create_osm_pgosm_flex_file = 'osm_pgosm_flex.sql'
    create_pgosm_road_file = 'pgosm_road.sql'
    create_replication_functions = 'replication_functions.sql'

    run_deploy_file(db_path=db_path, sql_filename=create_osm_file, schema_name=schema_name)
    run_deploy_file(db_path=db_path, sql_filename=create_osm_pgosm_flex_file, schema_name=schema_name)
    run_deploy_file(db_path=db_path, sql_filename=create_pgosm_road_file, schema_name=schema_name)
    run_deploy_file(db_path=db_path, sql_filename=create_replication_functions, schema_name=schema_name)

    if skip_qgis_style:
        LOGGER.info('Skipping QGIS styles')
    else:
        LOGGER.info('Loading QGIS styles')
        qgis_styles.load_qgis_styles(db_path=db_path,
                                     db_name=pg_conn_parts()['pg_db'])


def run_insert_pgosm_road(db_path: str, schema_name: str):
    """Runs script to load data to pgosm.road table.

    Parameters
    ------------------------
    db_path : str
    schema_name : str
        Schema name for OpenStreetMap data
    """
    sql_filename = 'roads-us.sql'
    run_deploy_file(db_path=db_path, sql_filename=sql_filename,
                    schema_name=schema_name, subfolder='data')


def run_deploy_file(db_path: str, sql_filename: str, schema_name: str,
                    subfolder: str='deploy'):
    """Run a SQL script under the deploy path.  Used to setup PgOSM Flex DB.

    Parameters
    ---------------------------
    db_path : str
        Path to folder with SQL scripts.
    sql_filename : sql_filename
    subfolder : str
        Set subfolder under db_path.
        Default: deploy
    schema_name : str
        Schema name for OpenStreetMap data
    """
    full_path = os.path.join(db_path, subfolder, sql_filename)
    LOGGER.info(f'Deploying {full_path}')

    with open(full_path) as f:
        deploy_sql = f.read()

    deploy_sql = deploy_sql.format(schema_name=schema_name)

    with get_db_conn(conn_string=get_db_conn_string()) as conn:
        cur = conn.cursor()
        cur.execute(deploy_sql)
        LOGGER.debug(f'Ran SQL in {sql_filename}')


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


def pgosm_nested_admin_polygons(flex_path: str, schema_name: str):
    """Runs stored procedure to calculate nested admin polygons via psql.

    Parameters
    ----------------------
    flex_path : str
    schema_name : str
    """
    sql_raw = f'CALL {schema_name}.build_nested_admin_polygons();'

    conn_string = get_db_conn_string()
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

    with get_db_conn(conn_string=get_db_conn_string()) as conn:
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

    conn_string = get_db_conn_string()
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
    conn_string = get_db_conn_string()
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


def log_import_message(import_id, msg, schema_name):
    """Logs msg to database in osm.pgosm_flex for import_uuid.

    Parameters
    -------------------------------
    import_id : int
    msg : str
    schema_name: str
    """
    sql_raw = """
UPDATE {schema_name}.pgosm_flex
    SET import_status = %(msg)s
    WHERE id = %(import_id)s
;
"""
    sql_raw = sql_raw.format(schema_name=schema_name)
    with get_db_conn(conn_string=get_db_conn_string()) as conn:
        params = {'import_id': import_id, 'msg': msg}
        cur = conn.cursor()
        cur.execute(sql_raw, params=params)


def get_prior_import(schema_name: str) -> dict:
    """Gets the latest import details from osm.pgosm_flex.

    Parameters
    --------------------
    schema_name : str

    Returns
    --------------------
    results : dict
    """
    sql_raw = """
SELECT id, osm_date, region, layerset, import_status,
        import_mode ->> 'replication' AS replication,
        import_mode ->> 'update' AS use_update,
        import_mode,
        split_part(pgosm_flex_version, '-', 1) AS pgosm_flex_version_no_hash
    FROM {schema_name}.pgosm_flex
    ORDER BY imported DESC
    LIMIT 1
;
"""
    sql_raw = sql_raw.format(schema_name=schema_name)
    with get_db_conn(conn_string=get_db_conn_string()) as conn:
        cur = conn.cursor(row_factory=psycopg.rows.dict_row)
        results = cur.execute(sql_raw).fetchone()

    if isinstance(results, type(None)):
        results = {}

    return results

    