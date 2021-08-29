# Using PgOSM-Flex within Docker

This README provides details about running PgOSM-Flex using the image defined
in `Dockerfile` and the script loaded from `docker/pgosm_flex.py`.


## Setup and Run Container

Create directory for the `.osm.pbf` file and output `.sql` file.

```bash
mkdir ~/pgosm-data
```


Set environment variables for the temporary Postgres connection in Docker.

```bash
export POSTGRES_USER=postgres
export POSTGRES_PASSWORD=mysecretpassword
```


Start the `pgosm` Docker container to make PostgreSQL/PostGIS available.
This command exposes Postgres inside Docker on port 5433 and establishes links
to the local directory created above (`~/pgosm-data`).
Using `-v /etc/localtime:/etc/localtime:ro` allows the Docker image to use
your the host machine's timezone, important when for archiving PBF & MD5 files by date.


```bash
docker run --name pgosm -d --rm \
    -v ~/pgosm-data:/app/output \
    -v /etc/localtime:/etc/localtime:ro \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    -p 5433:5432 -d rustprooflabs/pgosm-flex
```

## Run PgOSM-Flex

The following `docker exec` command runs PgOSM Flex to load the District of Columbia
region

The command  `python3 docker/pgosm_flex.py` runs the full process. The
script uses a region (`north-america/us`) and sub-region (`district-of-columbia`)
that must match values in URLs from the Geofabrik download server.
The 3rd parameter tells the script the server has 8 GB RAM available for osm2pgsql, Postgres, and the OS.  The PgOSM-Flex layer set is defined (`run-all`).


```bash
docker exec -it \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD -e POSTGRES_USER=$POSTGRES_USER \
    pgosm python3 docker/pgosm_flex.py \
    --layerset=run-all --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia
```


## Customize PgOSM-Flex

See full set of options via `--help`.

```bash
docker exec -it pgosm python3 docker/pgosm_flex.py --help
```

```bash
Usage: pgosm_flex.py [OPTIONS]

  Logic to run PgOSM Flex within Docker.

Options:
  --layerset TEXT     Layer set from PgOSM Flex to load. e.g. run-all
                      [default: (run-all);required]
  --ram INTEGER       Amount of RAM in GB available on the server running this
                      process.  [default: 4;required]
  --region TEXT       Region name matching the filename for data sourced from
                      Geofabrik. e.g. north-america/us  [default: (north-
                      america/us);required]
  --subregion TEXT    Sub-region name matching the filename for data sourced
                      from Geofabrik. e.g. district-of-columbia  [default:
                      (district-of-columbia)]
  --srid TEXT         SRID for data in PostGIS.
  --pgosm-date TEXT   Date of the data in YYYY-MM-DD format. Set to historic
                      date to load locally archived PBF/MD5 file, will fail if
                      both files do not exist.
  --language TEXT     Set default language in loaded OpenStreetMap data when
                      available.  e.g. 'en' or 'kn'.
  --schema-name TEXT  Coming soon
  --skip-nested       When True, skips calculating nested admin polygons. Can
                      be time consuming on large regions.
  --data-only         When True, skips running Sqitch and importing QGIS
                      Styles.
  --skip-dump         Skips the final pg_dump at the end. Useful for local
                      testing when not loading into more permanent instance.
  --debug             Enables additional log output
  --basepath TEXT     Debugging option. Used when testing locally and not
                      within Docker
  --help              Show this message and exit.
```

An example of running with all current options, except `--basepath` which is only
used during development.

```bash
docker exec -it \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD  -e POSTGRES_USER=$POSTGRES_USER \
    pgosm python3 docker/pgosm_flex.py \
    --layerset=run-all \
    --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia \
    --schema-name=osm_dc \
    --pgosm-date="2021-03-11" \
    --language="en" \
    --srid="4326" \
    --data-only \
    --skip-dump \
    --skip-nested \
    --debug
```


## Skip nested polygon calculation

Use `--skip-nested` to bypass the calculation of nested admin polygons.

The default is to run the nested polygon calculation. This can take considerable time on larger regions or may
be otherwise unwanted.


## Configure Postgres in Docker

Add customizations with the `-c` switch, e.g. `-c shared_buffers=1GB`,
to customize Postgres' configuration at run-time in Docker.


```bash
docker run --name pgosm -d --rm \
    -v ~/pgosm-data:/app/output \
    -v /etc/localtime:/etc/localtime:ro \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    -p 5433:5432 -d rustprooflabs/pgosm-flex \
    -c shared_buffers=1GB \
    -c maintenance_work_mem=1GB \
    -c checkpoint_timeout=300min \
    -c max_wal_senders=0 -c wal_level=minimal \
    -c checkpoint_completion_target=0.9 \
    -c random_page_cost=1.0
```



