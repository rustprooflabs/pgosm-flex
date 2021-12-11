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

Ensure the docker container is running.

```bash
docker ps -a | grep pgosm
```

> The most common reason the Docker container fails to run is not setting the `$POSTGRES_PASSWORD` env var.


## Run PgOSM-Flex

The following `docker exec` command runs PgOSM Flex to load the District of Columbia
region.
The command  `python3 docker/pgosm_flex.py` runs the full process. The
script uses a region (`--region=north-america/us`) and
sub-region (`--subregion=district-of-columbia`).
The region/subregion values must the URL pattern used by the Geofabrik download server,
see the [Regions and Subregions](#regions-and-subregions) section.

The `--ram=8` parameter defines the total system RAM available and is used by
internal logic to determine the best osm2pgsql options to use.
When running on hardware dedicated to this process it is safe to define the total
system RAM.  If the process is on a computer with other responsibilities, such
as your laptop, feel free to lower this value.


```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia
```

For the best in-Docker performance you will need to
[tune the internal Postgres config](#configure-postgres-in-docker) appropriately
for your hardware.
See the [osm2pgsql documentation](https://osm2pgsql.org/doc/manual.html#tuning-the-postgresql-server) for more on tuning Postgres for this
process.


## Regions and Subregions

The `--region` and `--subregion` definitions must match
the Geofabrik URL scheme.  This can be a bit confusing
as larger subregions can contain smaller subregions.

The example above to process the `district-of-columbia` subregion defines
`--region=north-america/us`.  You cannot, unfortunately, drop off
the `--subregion` to load the U.S. subregion. Attempting this results
in a `ValueError`.

To load the U.S. subregion, the `us` portion drops out of `--region`
and moves to `--subregion`.

```bash
docker exec -it pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america \
    --subregion=us
```


## Customize PgOSM-Flex

See full set of options via `--help`.  The required option (`--ram`) and the
commonly used `--region` and `--subregion` are listed first. The remainder
of the options are listed in alphabetical order.


```bash
docker exec -it pgosm python3 docker/pgosm_flex.py --help
```

```bash
Usage: pgosm_flex.py [OPTIONS]

  Run PgOSM Flex within Docker to automate osm2pgsql flex processing.

Options:
  --ram FLOAT           Amount of RAM in GB available on the machine running
                        this process. Used to determine appropriate osm2pgsql
                        command via osm2pgsql-tuner recommendation engine.
                        [required]
  --region TEXT         Region name matching the filename for data sourced
                        from Geofabrik. e.g. north-america/us. Optional when
                        --input-file is specified, otherwise required.
  --subregion TEXT      Sub-region name matching the filename for data sourced
                        from Geofabrik. e.g. district-of-columbia
  --basepath TEXT       Debugging option. Used when testing locally and not
                        within Docker
  --data-only           When set, skips running Sqitch and importing QGIS
                        Styles.
  --debug               Enables additional log output
  --input-file TEXT     Set explicit filepath to input osm.pbf file. Overrides
                        default file handling, archiving, and MD5 checksum.
  --layerset TEXT       Layerset to load. Defines name of included layerset
                        unless --layerset-path is defined.  [required]
  --layerset-path TEXT  Custom path to load layerset INI from. Custom paths
                        should be mounted to Docker via docker run -v ...
  --language TEXT       Set default language in loaded OpenStreetMap data when
                        available.  e.g. 'en' or 'kn'.
  --pgosm-date TEXT     Date of the data in YYYY-MM-DD format. If today
                        (default), automatically downloads when files not
                        found locally. Set to historic date to load locally
                        archived PBF/MD5 file, will fail if both files do not
                        exist.
  --schema-name TEXT    Change the final schema name, defaults to 'osm'.
  --skip-dump           Skips the final pg_dump at the end. Useful for local
                        testing when not loading into more permanent instance.
  --skip-nested         When set, skips calculating nested admin polygons. Can
                        be time consuming on large regions.
  --srid TEXT           SRID for data loaded by osm2pgsql to PostGIS. Defaults
                        to 3857
  --help                Show this message and exit.
```

An example of running with all current options, except `--basepath` which is only
used during development.

```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --layerset=poi \
    --layerset-path=/custom-layerset/ \
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

## Use custom layersets

See [LAYERSETS.md](LAYERSETS.md) for details about creating custom layersets.

To use the `--layerset-path` option for custom layerset
definitions, link the directory containing custom styles
to the Docker container in the `docker run` command.
The custom styles will be available inside the container under
`/custom-layerset`.


```bash
docker run --name pgosm -d --rm \
    -v ~/pgosm-data:/app/output \
    -v /etc/localtime:/etc/localtime:ro \
    -v ~/custom-layerset:/custom-layerset \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    -p 5433:5432 -d rustprooflabs/pgosm-flex
```

Define the layerset name (`--layerset=poi`) and path
(`--layerset-path`) to the `docker exec`.


```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --layerset=poi \
    --layerset-path=/custom-layerset/ \
    --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia
```


## Skip nested polygon calculation

Use `--skip-nested` to bypass the calculation of nested admin polygons.
The nested polygon process can take considerable time on larger regions or may
be otherwise unwanted.

## Skip data export

By default the `.sql` file is created with `pg_dump` for easy loading into one or
more Postgres databases.  If this file is not needed use `--skip-dump`. This saves
time and reduces disk space consumed by the process.


## Configure Postgres in Docker

Add customizations with the `-c` switch, e.g. `-c shared_buffers=1GB`,
to customize Postgres' configuration at run-time in Docker.
See the [osm2pgsql documentation](https://osm2pgsql.org/doc/manual.html#preparing-the-database)
for recommendations on a server with 64 GB of RAM.

This `docker run` command has been tested with 16GB RAM and 4 CPU (8 threads) with the Colorado
subregion.  Configuring Postgres in-Docker runs 7-14% faster than the default
Postgres in-Docker configuration.


```bash
docker run --name pgosm -d --rm \
    -v ~/pgosm-data:/app/output \
    -v /etc/localtime:/etc/localtime:ro \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    -p 5433:5432 -d rustprooflabs/pgosm-flex \
    -c shared_buffers=512MB \
    -c work_mem=50MB \
    -c maintenance_work_mem=4GB \
    -c checkpoint_timeout=300min \
    -c max_wal_senders=0 -c wal_level=minimal \
    -c max_wal_size=10GB \
    -c checkpoint_completion_target=0.9 \
    -c random_page_cost=1.0
```


The `docker exec` command used for the timings.

```bash
time docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america/us \
    --subregion=colorado \
    --layerset=basic \
    --pgosm-date=2021-10-08
```
