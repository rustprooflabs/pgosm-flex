#!/usr/bin/env python3
"""Python script to run PgOSM Flex within Docker container.

Docker image available on Docker Hub
    https://hub.docker.com/r/rustprooflabs/pgosm-flex

Usage instructions:
    https://github.com/rustprooflabs/pgosm-flex/blob/main/docs/DOCKER-RUN.md
"""
import configparser
import logging
import os
from pathlib import Path
import sys

import click

import osm2pgsql_recommendation as rec
import db
import geofabrik
import helpers
from import_mode import ImportMode


@click.command()
# Required and most common options first
@click.option('--ram', required=True,
              type=float,
              help='Amount of RAM in GB available on the machine running the Docker container. This is used to determine the appropriate osm2pgsql command via osm2pgsql-tuner recommendation engine.')
@click.option('--region', required=False,
              help='Region name matching the filename for data sourced from Geofabrik. e.g. north-america/us. Optional when --input-file is specified, otherwise required.')
@click.option('--subregion', required=False,
              help='Sub-region name matching the filename for data sourced from Geofabrik. e.g. district-of-columbia')
# Remainder of options in alphabetical order
@click.option('--debug', is_flag=True,
              help='Enables additional log output')
@click.option('--force', is_flag=True,
              help='Danger!  Forces PgOSM Flex to load the data even if this will overwrite pre-existing data. See https://pgosm-flex.com/force-load.html for more.')
@click.option('--input-file',
              required=False,
              default=None,
              help='Set filename or absolute filepath to input osm.pbf file. Overrides default file handling, archiving, and MD5 checksum validation. Filename is assumed under /app/output unless absolute path is used.')
@click.option('--layerset', required=True,
              default='default',
              help='Layerset to load. Defines name of included layerset unless --layerset-path is defined.')
@click.option('--layerset-path', required=False,
              help='Custom path to load layerset INI from. Custom paths should be mounted to Docker via docker run -v ...')
@click.option('--language', default=None,
              envvar="PGOSM_LANGUAGE",
              help="Set default language in loaded OpenStreetMap data when available.  e.g. 'en' or 'kn'.")
@click.option('--pg-dump', default=False, is_flag=True,
              help='Uses pg_dump after processing is completed to enable easily load OpenStreetMap data into a different database')
@click.option('--pgosm-date', required=False,
              default=helpers.get_today(),
              envvar="PGOSM_DATE",
              help="Date of the data in YYYY-MM-DD format. If today (default), automatically downloads when files not found locally. Set to historic date to load locally archived PBF/MD5 file, will fail if both files do not exist.")
@click.option('--replication',
              default=False,
              is_flag=True,
              help='Replication mode enables updates via osm2pgsql-replication.')
@click.option('--skip-nested',
              default=False,
              is_flag=True,
              help='When set, skips calculating nested admin polygons. Can be time consuming on large regions.')
@click.option('--skip-qgis-style',
              default=False,
              is_flag=True,
              help="When set, skips running importing QGIS Styles.")
@click.option('--srid', required=False, default=helpers.DEFAULT_SRID,
              envvar="PGOSM_SRID",
              help="SRID for data loaded by osm2pgsql to PostGIS. Defaults to 3857")
@click.option('--sp-gist', default=False, is_flag=True,
              help='When set, builds SP-GIST indexes on geom column instead of the default GIST indexes.')
@click.option('--update', default=None,
              type=click.Choice(['append', 'create'], case_sensitive=True),
              help='EXPERIMENTAL - Wrap around osm2pgsql create v. append modes, without using osm2pgsql-replication.')
def run_pgosm_flex(ram, region, subregion, debug, force,
                    input_file, layerset, layerset_path, language, pg_dump,
                    pgosm_date, replication, skip_nested,
                    skip_qgis_style, srid, sp_gist, update):
    """Run PgOSM Flex within Docker to automate osm2pgsql flex processing.
    """
    paths = get_paths()
    setup_logger(debug)
    logger = logging.getLogger('pgosm-flex')
    logger.info('PgOSM Flex starting...')

    if replication and (update is not None):
        err_msg = 'The --replication and --update features are mutually exclusive. Use one or the other.'
        logger.error(err_msg)
        sys.exit(err_msg)
    # End of input validation

    validate_region_inputs(region, subregion, input_file)
    if region is None and input_file:
        region = input_file

    helpers.set_env_vars(region, subregion, srid, language, pgosm_date,
                         layerset, layerset_path, sp_gist, replication)
    db.wait_for_postgres()
    if force and db.pg_conn_parts()['pg_host'] == 'localhost':
        msg = 'Using --force with the built-in database is unnecessary.'
        msg += ' The pgosm database is always dropped and recreated when'
        msg += ' running on localhost (in Docker).'
        logger.warning(msg)

    if replication:
        replication_update = check_replication_exists()
    else:
        replication_update = False

    # Setting pgosm_date when replication is updating isn't an option
    if replication_update:
        if pgosm_date != helpers.get_today():
            logger.warning('Overriding --pgosm-date due to replication update mode, setting to today')
            pgosm_date = helpers.get_today()
            os.environ['PGOSM_DATE'] = pgosm_date

    logger.debug(f'UPDATE setting:  {update}')
    # Warning: Reusing the module's name here as import_mode...
    import_mode = ImportMode(replication=replication,
                             replication_update=replication_update,
                             update=update,
                             force=force)

    db.prepare_pgosm_db(skip_qgis_style=skip_qgis_style,
                        db_path=paths['db_path'],
                        import_mode=import_mode)

    prior_import = db.get_prior_import()

    if not import_mode.okay_to_run(prior_import):
        msg = 'Not okay to run PgOSM Flex. Exiting'
        logger.error(msg)
        sys.exit(msg)

    # There's probably a better way to get this data out, but this worked right
    # away and I'm moving on.  I'm breaking enough other things that this seemed
    # to be a good compromise today.
    vers_lines = []
    helpers.run_command_via_subprocess(cmd=['osm2pgsql', '--version'],
                                       cwd='/usr/bin/',
                                       output_lines=vers_lines)

    import_id = db.start_import(pgosm_region=helpers.get_region_combined(region, subregion),
                                pgosm_date=pgosm_date,
                                srid=srid,
                                language=language,
                                layerset=layerset,
                                git_info=helpers.get_git_info(),
                                osm2pgsql_version=vers_lines,
                                import_mode=import_mode)

    logger.info(f'Started import id {import_id}')

    if import_mode.replication_update:
        logger.info('Running osm2pgsql-replication in update mode')
        success = run_replication_update(skip_nested=skip_nested,
                                         flex_path=paths['flex_path'])
    else:
        logger.info('Running osm2pgsql')
        success = run_osm2pgsql_standard(input_file=input_file,
                                         out_path=paths['out_path'],
                                         flex_path=paths['flex_path'],
                                         ram=ram,
                                         skip_nested=skip_nested,
                                         import_mode=import_mode,
                                         debug=debug)

    if not success:
        msg = 'PgOSM Flex completed with errors. Details in output'
        db.log_import_message(import_id=import_id, msg='Failed')
        logger.warning(msg)
        sys.exit(msg)

    db.log_import_message(import_id=import_id, msg='Completed')

    dump_database(input_file=input_file,
                  out_path=paths['out_path'],
                  pg_dump=pg_dump,
                  skip_qgis_style=skip_qgis_style)

    logger.info('PgOSM Flex complete!')


def run_osm2pgsql_standard(input_file, out_path, flex_path, ram, skip_nested,
                           import_mode, debug):
    """Runs standard osm2pgsql command and optionally inits for replication
    (osm2pgsql-replication) mode.

    Parameters
    ---------------------------
    input_file : str
    out_path : str
    flex_path : str
    ram : float
    skip_nested : boolean
    import_mode : import_mode.ImportMode
    debug : boolean

    Returns
    ---------------------------
    post_processing : boolean
        Indicates overall success/failure of the steps within this function.
    """
    logger = logging.getLogger('pgosm-flex')

    if input_file is None:
        geofabrik.prepare_data(out_path=out_path)
        pbf_filename = geofabrik.get_region_filename()
    else:
        pbf_filename = input_file

    osm2pgsql_command = rec.osm2pgsql_recommendation(ram=ram,
                                                     pbf_filename=pbf_filename,
                                                     out_path=out_path,
                                                     import_mode=import_mode)

    run_osm2pgsql(osm2pgsql_command=osm2pgsql_command, flex_path=flex_path,
                  debug=debug)

    if not skip_nested:
        skip_nested = check_layerset_places(flex_path)

    post_processing = run_post_processing(flex_path=flex_path,
                                          skip_nested=skip_nested,
                                          import_mode=import_mode)

    if import_mode.replication:
        run_osm2pgsql_replication_init(pbf_path=out_path,
                                       pbf_filename=pbf_filename)
    else:
        logger.debug('Not using replication mode')

    if input_file is None:
        geofabrik.remove_latest_files(out_path)

    return post_processing


def run_replication_update(skip_nested, flex_path):
    """Runs osm2pgsql-replication between the DB start/finish steps.

    Parameters
    -----------------------
    skip_nested : bool
    flex_path : str

    Returns
    ---------------------
    bool
        Indicates success/failure of replication process.
    """
    logger = logging.getLogger('pgosm-flex')
    conn_string = db.connection_string()
    db.osm2pgsql_replication_start()

    update_cmd = """
osm2pgsql-replication update -d $PGOSM_CONN \
    -- \
    --output=flex --style=./run.lua \
    --slim \
    -d $PGOSM_CONN
"""
    update_cmd = update_cmd.replace('-d $PGOSM_CONN', f'-d {conn_string}')
    returncode = helpers.run_command_via_subprocess(cmd=update_cmd.split(),
                                                    cwd=flex_path,
                                                    print=True)

    if returncode != 0:
        err_msg = f'Failure. Return code: {returncode}'
        logger.warning(err_msg)
        return False

    db.osm2pgsql_replication_finish(skip_nested=skip_nested)
    logger.info('osm2pgsql-replication update complete')
    return True


def validate_region_inputs(region, subregion, input_file):
    """Ensures the combination of region, subregion and input_file is valid.

    No return, raises error when invalid.

    Parameters
    -----------------------
    region : str
    subregion : str
    input_file : str
    """
    if region is None and input_file is None:
        raise ValueError('Either --region or --input-file must be provided')

    if region is None and subregion is not None:
        raise ValueError('Cannot use --subregion without --region')

    if region is not None:
        if '/' in region and subregion is None:
            err_msg = 'Region provided appears to include subregion. '
            err_msg += 'The portion after the final "/" in the Geofabrik URL '
            err_msg += 'should be the --subregion.'
            raise ValueError(err_msg)


def setup_logger(debug):
    """Prepares logging.

    Parameters
    ------------------------------
    debug : bool
        Enables debug mode when True.  INFO when False.
    """
    if debug:
        log_level = logging.DEBUG
    else:
        log_level = logging.INFO

    log_format = '%(asctime)s:%(levelname)s:%(name)s:%(module)s:%(message)s'
    logging.basicConfig(stream=sys.stdout,
                        level=log_level,
                        filemode='w',
                        format=log_format)

    # Reduce verbosity of urllib3 logging
    logging.getLogger('urllib3').setLevel(logging.INFO)
    logger = logging.getLogger('pgosm-flex')
    logger.debug('Logger configured')


def get_paths():
    """Returns dictionary of various paths used.

    Ensures `out_path` exists.

    Returns
    -------------------
    paths : dict
    """
    base_path = '/app'

    db_path = os.path.join(base_path, 'db')
    out_path = os.path.join(base_path, 'output')
    flex_path = os.path.join(base_path, 'flex-config')
    paths = {'base_path': base_path,
             'db_path': db_path,
             'out_path': out_path,
             'flex_path': flex_path}

    Path(out_path).mkdir(parents=True, exist_ok=True)
    return paths


def get_export_filename(input_file):
    """Returns the .sql filename to use for pg_dump.

    Parameters
    ----------------------
    input_file : str

    Returns
    ----------------------
    filename : str
    """
    # always set internally, even with --input-file and no --region
    region = os.environ.get('PGOSM_REGION').replace('/', '-')
    subregion = os.environ.get('PGOSM_SUBREGION')
    layerset = os.environ.get('PGOSM_LAYERSET')
    pgosm_date = os.environ.get('PGOSM_DATE')

    if subregion:
        subregion = subregion.replace('/', '-')

    if input_file:
        # Assumes .osm.pbf
        base_name = input_file[:-8]
        filename = f'{base_name}-{layerset}-{pgosm_date}.sql'
    elif subregion is None:
        filename = f'{region}-{layerset}-{pgosm_date}.sql'
    else:
        filename = f'{region}-{subregion}-{layerset}-{pgosm_date}.sql'

    return filename


def get_export_full_path(out_path, export_filename):
    """If `export_filename` is an absolute path, `out_path` is not considered.

    Parameters
    -----------------
    out_path : str
    export_filename : str

    Returns
    -----------------
    export_path : str
    """
    if os.path.isabs(export_filename):
        export_path = export_filename
    else:
        export_path = os.path.join(out_path, export_filename)

    return export_path


def run_osm2pgsql(osm2pgsql_command, flex_path, debug):
    """Runs the provided osm2pgsql command.

    Parameters
    ----------------------
    osm2pgsql_command : str
    flex_path : str
    debug : boolean
    """
    logger = logging.getLogger('pgosm-flex')
    logger.info('Running osm2pgsql')
        
    returncode = helpers.run_command_via_subprocess(cmd=osm2pgsql_command.split(),
                                                    cwd=flex_path,
                                                    print=True)

    if returncode != 0:
        err_msg = f'Failed to run osm2pgsql. Return code: {returncode}'
        logger.error(err_msg)
        sys.exit(f'{err_msg} - Check the log output for details')

    logger.info('osm2pgsql completed')


def check_layerset_places(flex_path):
    """If `place` layer is not included `skip_nested` should be true.

    Parameters
    ------------------------
    flex_path : str

    Returns
    ------------------------
    skip_nested : boolean
    """
    logger = logging.getLogger('pgosm-flex')
    layerset = os.environ.get('PGOSM_LAYERSET')
    layerset_path = os.environ.get('PGOSM_LAYERSET_PATH')

    if layerset_path is None:
        layerset_path = os.path.join(flex_path, 'layerset')
        logger.info(f'Using default layerset path {layerset_path}')

    ini_file = os.path.join(layerset_path, f'{layerset}.ini')
    config = configparser.ConfigParser()
    config.read(ini_file)
    try:
        place = config['layerset']['place']
    except KeyError:
        logger.debug('Place layer not defined, setting skip_nested')
        return True

    if place:
        logger.debug('Place layer is defined as true. Not setting skip_nested')
        return False

    logger.debug('Place set to false, setting skip_nested')
    return True


def run_post_processing(flex_path, skip_nested, import_mode):
    """Runs steps following osm2pgsql import.

    Post-processing SQL scripts and (optionally) calculate nested admin polgyons

    Parameters
    ----------------------
    flex_path : str
    skip_nested : bool
    import_mode : import_mode.ImportMode

    Returns
    ----------------------
    status : bool
    """
    logger = logging.getLogger('pgosm-flex')

    if not import_mode.run_post_sql:
        logger.info('Running with --update append: Skipping post-processing SQL')
        return True

    post_processing_sql = db.pgosm_after_import(flex_path)

    if skip_nested:
        logger.info('Skipping calculating nested polygons')
    else:
        logger.info('Calculating nested polygons')
        db.pgosm_nested_admin_polygons(flex_path)

    if not post_processing_sql:
        return False
    return True


def dump_database(input_file, out_path, pg_dump, skip_qgis_style):
    """Runs pg_dump when necessary to export the processed OpenStreetMap data.

    Parameters
    -----------------------
    input_file : str
    out_path : str
    pg_dump : bool
    skip_qgis_style : bool
    """
    if pg_dump:
        export_filename = get_export_filename(input_file)
        export_path = get_export_full_path(out_path, export_filename)

        db.run_pg_dump(export_path=export_path,
                       skip_qgis_style=skip_qgis_style)
    else:
        logging.getLogger('pgosm-flex').info('Skipping pg_dump')


def check_replication_exists():
    """Checks if replication already setup, if so should only run update.

    Returns
    -------------------
    status : bool
    """
    logger = logging.getLogger('pgosm-flex')
    check_cmd = "osm2pgsql-replication status -d $PGOSM_CONN "
    logger.debug(f'Command to check DB for replication status:\n{check_cmd}')
    conn_string = db.connection_string()
    check_cmd = check_cmd.replace('-d $PGOSM_CONN', f'-d {conn_string}')

    returncode = helpers.run_command_via_subprocess(cmd=check_cmd.split(),
                                                    cwd=None)

    if returncode != 0:
        logger.info('Replication not previously set up, fresh import.')
        logger.debug(f'Return code: {returncode}')
        return False

    logger.debug('Replication set up, candidate for update.')
    return True


def run_osm2pgsql_replication_init(pbf_path, pbf_filename):
    """Runs osm2pgsql-replication init to support replication mode.

    Parameters
    ---------------------
    pbf_path : str
    pbf_filename : str
    """
    logger = logging.getLogger('pgosm-flex')
    pbf_path = os.path.join(pbf_path, pbf_filename)
    init_cmd = 'osm2pgsql-replication init -d $PGOSM_CONN '
    init_cmd += f'--osm-file {pbf_path}'
    logger.debug(f'Initializing DB for replication with command:\n{init_cmd}')
    conn_string = db.connection_string()
    init_cmd = init_cmd.replace('-d $PGOSM_CONN', f'-d {conn_string}')

    returncode = helpers.run_command_via_subprocess(cmd=init_cmd.split(),
                                                    cwd=None,
                                                    print=True)

    if returncode != 0:
        err_msg = f'Failed to run osm2pgsql-replication. Return code: {returncode}'
        logger.error(err_msg)
        sys.exit(f'{err_msg} - Check the log output for details.')

    logger.debug('osm2pgsql-replication init completed.')


if __name__ == "__main__":
    logging.getLogger('pgosm-flex').info('Running PgOSM Flex!')
    run_pgosm_flex()
