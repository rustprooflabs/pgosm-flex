"""Module to allow adding pgBouncer functionality.
"""
import logging
import psycopg
import subprocess

import db


LOGGER = logging.getLogger('pgosm-flex')

PGBOUNCER_USER_LIST_PATH = '/etc/pgbouncer/userlist.txt'
PGBOUNCER_INI_PATH = '/etc/pgbouncer/pgbouncer.ini'

PGBOUNCER_INI_TEMPLATE = """[databases]
{pg_db} = host={pg_host} port={pg_port} dbname={pg_db}

[pgbouncer]
listen_port = 6432
listen_addr = localhost
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
logfile = /var/log/pgbouncer/pgbouncer.log
pidfile = /var/run/pgbouncer/pgbouncer.pid
admin_users = postgres
max_client_conn = 300
default_pool_size = {pgbouncer_pool_size}
max_prepared_statements = 500
"""
"""str : Shell of pgbouncer.ini used to configure pgBouncer."""

PGBOUNCER_USER_LIST_TEMPLATE = """
"{pg_user}" "{pg_pass}"
"""
"""str : Shell of userlist.txt to provide authentication to pgBouncer."""


def setup(pgbouncer_pool_size: int):
    """Sets up configuration files for pgBouncer.

    Parameters
    ---------------------------
    pgbouncer_pool_size : int
    """
    if pgbouncer_pool_size < 1:
        raise ValueError(f'Invalid pgbouncer_pool_size.  Must be >= 1.  Value {pgbouncer_pool_size}')

    db_parts = db.pg_conn_parts()

    user_list = PGBOUNCER_USER_LIST_TEMPLATE.format(pg_user=db_parts['pg_user'],
                                                    pg_pass=db_parts['pg_pass']
                                                    )

    LOGGER.warning('Saving password in plain text within the container for pgBouncer.')
    with open(PGBOUNCER_USER_LIST_PATH, "w") as user_file:
        user_file.write(user_list)

    LOGGER.info(f'Setting up pgBouncer configuration files with pool size {pgbouncer_pool_size}')
    pgbouncer_ini = PGBOUNCER_INI_TEMPLATE.format(pg_host=db_parts['pg_host'],
                                                  pg_port=db_parts['pg_port'],
                                                  pg_db=db_parts['pg_db'],
                                                  pgbouncer_pool_size=pgbouncer_pool_size
                                                  )

    with open(PGBOUNCER_INI_PATH, "w") as ini_file:
        ini_file.write(pgbouncer_ini)


def run():
    """Wrapper of the private _run() function.  This uses error handling to
    stop and re-start the pgBouncer service since the # of connections is
    defined at docker exec time, not docker run. 
    """
    LOGGER.debug('Running pgbouncer as daemon')
    try:
        _run()
    except subprocess.CalledProcessError as err:
        LOGGER.debug('pgBouncer was already running.')
        stop()
        LOGGER.debug('Re-starting pgBouncer daemon')
        _run()

    LOGGER.info('pgBouncer started')


def _run():
    """Has the logic to run pgbouncer. Not wrapped in error handling here,
    letting outer method deal with that.
    """
    subprocess.run(
            ['/usr/bin/pgbouncer', "-d", PGBOUNCER_INI_PATH],
            capture_output=True,
            text=True,
            check=True,
            user='postgres'
        )


def stop():
    """Stops the pgbouncer service. Uses connection to pgbouncer database.
    """
    LOGGER.info('Shutting down the pgBouncer service.')
    sql_raw = "SHUTDOWN;"
    conn_string = db.connection_string(pgbouncer=True,
                                       pgbouncer_admin=True)

    # Writing this way instead of as with ... as conn b/c of how function returns
    # false.
    conn = db.get_db_conn(conn_string=conn_string)
    if not conn:
        LOGGER.warning('Unable to connect to pgbouncer to shutdown pgBouncer.  Probably not a problem.')
        return

    conn.autocommit = True
    try:
        conn.execute(sql_raw)
    except psycopg.OperationalError:
        LOGGER.debug('Disconnected.  This is the expected result.')

        