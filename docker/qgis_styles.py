"""PgOSM Flex module to handle loading QGIS styles to Postgres.
"""
import logging
import os
import subprocess

import db


LOGGER = logging.getLogger('pgosm-flex')


def load_qgis_styles(db_path, db_name):
    """Loads QGIS style data for easy formatting of most common layers.

    Parameters
    -------------------------
    db_path : str
        Base path to pgosm-flex/db directory
    db_name : str
    """
    LOGGER.info(f'Load QGIS styles to database {db_name}...')
    conn_string = os.environ['PGOSM_CONN']

    create_layer_style_table(db_path=db_path, conn_string=conn_string)
    populate_layer_style_staging(db_path=db_path, conn_string=conn_string)
    update_styles_db_name(db_name=db_name, conn_string=conn_string)
    load_staging_to_prod(db_path=db_path, conn_string=conn_string)


def create_layer_style_table(db_path, conn_string):
    """Ensures QGIS layer styles table exists.
 
    Parameters
    --------------------
    db_path : str
    conn_string : path
    """
    create_path = os.path.join(db_path,
                               'qgis-style',
                               'create_layer_styles.sql')

    with open(create_path, 'r') as file_in:
        create_sql = file_in.read()

    with db.get_db_conn(conn_string=conn_string) as conn:
        cur = conn.cursor()
        cur.execute(create_sql)
    LOGGER.debug('QGIS Style table created')


def populate_layer_style_staging(db_path, conn_string):
    """Loads data to public.layer_styles_staging using psql

    Parameters
    --------------------
    db_path : str
    conn_string : path
    """
    # Loading layer_styles data is done from files created by pg_dump, using
    # psql to reload is easiest
    cmds_populate = ['psql', '-d', conn_string,
                     '-f', 'qgis-style/layer_styles.sql']

    output = subprocess.run(cmds_populate,
                            text=True,
                            capture_output=True,
                            cwd=db_path,
                            check=False)

    LOGGER.debug(f'Output from loading QGIS style data: {output.stdout}')


def load_staging_to_prod(db_path, conn_string):
    """Loads data from public.layer_styles_staging to public.layer_styles.

    Parameters
    --------------------
    db_path : str
    conn_string : path
    """
    load_path = os.path.join(db_path,
                             'qgis-style',
                             '_load_layer_styles.sql')

    with open(load_path, 'r') as file_in:
        load_sql = file_in.read()

    with db.get_db_conn(conn_string=conn_string) as conn:
        cur = conn.cursor()
        cur.execute(load_sql)

    LOGGER.info('QGIS Style table populated')

    with db.get_db_conn(conn_string=conn_string) as conn:
        sql_clean = 'DELETE FROM public.layer_styles_staging;'
        cur = conn.cursor()
        cur.execute(sql_clean)

    LOGGER.debug('QGIS Style staging table cleaned')


def update_styles_db_name(db_name, conn_string):
    """
    Parameters
    ----------------------
    db_name : str
    conn_string : str
    """
    if db_name == 'pgosm':
        LOGGER.debug('Database name set to defaults. Update to layer styles not necessary')
        return

    sql_raw = """
UPDATE public.layer_styles_staging
    SET f_table_catalog = %(db_name)s
;
"""
    params = {'db_name': db_name}
    with db.get_db_conn(conn_string=conn_string) as conn:
        cur = conn.cursor()
        cur.execute(sql_raw, params=params)
        conn.commit()

    LOGGER.info(f'Updated QGIS layer styles for database {db_name}')

