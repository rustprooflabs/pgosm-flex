import click
import subprocess
import sys
import time
import osm2pgsql_recommendation as rec


@click.command()
@click.option('--layerset', required=True,
              prompt='PgOSM Flex Layer Set',
              help='Layer set from PgOSM Flex to load. e.g. run-all')
@click.option('--ram', required=True,
              prompt='Server RAM (GB)',
              help='Amount of RAM in GB available on the server running this process.')
@click.option('--region', required=True,
              prompt="Region name",
              help='Region name matching the filename for data sourced from Geofabrik. e.g. north-america/us')
@click.option('--subregion', required=False,
              prompt="Sub-region name",
              help='Sub-region name matching the filename for data sourced from Geofabrik. e.g. district-of-columbia')
@click.option('--pgosm-date', required=False,
              envvar="PGOSM_DATE")
def run_pgosm_flex(layerset, ram, region, subregion, pgosm_date):
    prepare_data(region=region, subregion=subregion, pgosm_date=pgosm_date)
    get_osm2pgsql_recommendation(region=region, ram=ram, layerset=layerset)
    wait_for_postgres()


def wait_for_postgres():
    """Ensures Postgres service is reliably ready for use.

    Required b/c Postgres process in Docker gets restarted shortly
    after starting.    
    """
    print('Checking for Postgres service to be available')

    required_checks = 2
    found = 0
    i = 0

    while found < required_checks:
        time.sleep(5)

        if _check_pg_up():
            found += 1
            print(f'Postgres up {found} times')

        if i % 5 == 0:
            print('Waiting...')

        if i > 100:
            sys.exit('ERROR - Postgres still not available. Exiting.')
        i += 1

    print('Database passed two checks - should be ready!')


def _check_pg_up():
    """Checks pg_isready for Postgres to be available.

    https://www.postgresql.org/docs/current/app-pg-isready.html
    """
    output = subprocess.run(['pg_isready'], text=True, capture_output=True)
    code = output.returncode
    if code == 0:
        return True
    elif code == 3:
        sys.exit('ERROR - Postgres check is misconfigured.')
    else:
        return False


def prepare_data(region, subregion, pgosm_date):
    # Check if data  region + subregion + date exists (and verifies MD5)

    # Download if Not

    # Verify MD5

    pass


def get_osm2pgsql_recommendation(region, ram, layerset):
    rec_cmd = rec.osm2pgsql_recommendation(region=region,
                                           ram=ram,
                                           output=None,
                                           layerset=layerset)
    print(rec_cmd)

if __name__ == "__main__":
    run_pgosm_flex()

