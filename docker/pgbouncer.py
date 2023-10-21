"""Module to allow adding pgBouncer functionality.
"""
import subprocess

import db


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
default_pool_size = 20
max_prepared_statements = 500
"""
"""str : Shell of pgbouncer.ini used to configure pgBouncer."""

PGBOUNCER_USER_LIST_TEMPLATE = """
"{pg_user}" "{pg_pass}"
"""
"""str : Shell of userlist.txt to provide authentication to pgBouncer."""


def setup():
    """Sets up configuration files for pgBouncer.
    """
    print('Setting up pgBouncer configuration files')
    db_parts = db.pg_conn_parts()

    user_list = PGBOUNCER_USER_LIST_TEMPLATE.format(pg_user=db_parts['pg_user'],
                                                    pg_pass=db_parts['pg_pass']
                                                    )

    print('WARNING: Saving password in plain text within the container for pgBouncer.')
    with open(PGBOUNCER_USER_LIST_PATH, "w") as user_file:
        user_file.write(user_list)

    pgbouncer_ini = PGBOUNCER_INI_TEMPLATE.format(pg_host=db_parts['pg_host'],
                                                  pg_port=db_parts['pg_port'],
                                                  pg_db=db_parts['pg_db']
                                                  )

    with open(PGBOUNCER_INI_PATH, "w") as ini_file:
        ini_file.write(pgbouncer_ini)


def run():
    print('Running pgbouncer as postgres user')
    subprocess.run(
        ['/usr/bin/pgbouncer', "-d", PGBOUNCER_INI_PATH],
        capture_output=True,
        text=True,
        check=True,
        user='postgres'
    )

