# Using PgOSM Flex

This README provides details about running PgOSM Flex using the image defined
in `Dockerfile` and the script loaded from `docker/pgosm_flex.py`.


## Directory for data files

Create directory for the `.osm.pbf` file and the output `.sql` file. The PBF and MD5 files
downloaded from Geofabrik are stored in this directory.
This directory location is assumed in subsequent `docker run` commands.
If you change the data file path be sure to adjust `-v ~/pgosm-data:/app/output`
appropriately to link your path.

```bash
mkdir ~/pgosm-data
```



## Run PgOSM Flex Container


Set environment variables for the temporary Postgres connection in Docker.


### Internal Postgres instance

The Postgres username and password are the minimum required parameters to use
the internal Postgres database instance.

```bash
export POSTGRES_USER=postgres
export POSTGRES_PASSWORD=mysecretpassword
```


Start the `pgosm` Docker container to make PostgreSQL/PostGIS available.
This command exposes Postgres inside Docker on port 5433 and establishes links
to the local directory created above (`~/pgosm-data`). If your data is stored in a
different location, update this value.

Using `-v /etc/localtime:/etc/localtime:ro` allows the Docker image to use
the host machine's timezone instead of UTC. This is important when determining if the data
to load should be the latest file (download) or a historic (local) file.


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

Run the processing with `docker exec`.

```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia
```



### External Postgres instance

The PgOSM Flex Docker image can be used with Postgres instance outside the
Docker container.

Prepare the database and permissions as described in
[POSTGRES-PERMISSIONS.md](POSTGRES-PERMISSIONS.md).


Set environment variables to define the connection.

```bash
export POSTGRES_USER=your_login_role
export POSTGRES_PASSWORD=mysecretpassword
export POSTGRES_HOST=your-host-or-ip
export POSTGRES_DB=your_db_name
export POSTGRES_PORT=5432
```

----

Note: The `POSTGRES_HOST` value is in relation to the Docker container.
Using `localhost` refers to the Docker container and will use the Postgres instance
within the Docker container, not your host running the Docker container.
Use `ip addr` to find your local host's IP address and provide that.

----

Run the container with the additional environment variables.

```bash
docker run --name pgosm -d --rm \
    -v ~/pgosm-data:/app/output \
    -v /etc/localtime:/etc/localtime:ro \
    -e POSTGRES_USER=$POSTGRES_USER \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    -e POSTGRES_HOST=$POSTGRES_HOST \
    -e POSTGRES_DB=$POSTGRES_DB \
    -e POSTGRES_PORT=$POSTGRES_PORT \
    -p 5433:5432 -d rustprooflabs/pgosm-flex
```

> Note: Setting `POSTGRES_HOST` to anything but `localhost` disables the drop/create database step. This means the target database must be created prior to running PgOSM Flex.


The `docker exec` command is the same as when using the internal Postgres instance.

```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia
```


## Use `--replication` to keep data fresh

> The `--replication` mode seems to be stable as of 0.7.0.  It was added as an experimental feature in 0.4. (originally under the --append option).


PgOSM Flex's `--replication` mode wraps around the `osm2pgsql-replication` package
included with `osm2pgsql`.  The first time running an import with `--replication`
mode runs osm2pgsql normally, with `--slim` mode and without `--drop`.
After osm2pgsql completes, `osm2pgsql-replication init ...` is ran to setup
the DB for updates.
This mode of operation results in larger database as the intermediate osm2pgsql
tables (`--slim`) must be left in the database (no `--drop`).


> Important:  The original `--append` option is now under `--replication`. The `--append` option was removed in PgOSM Flex 0.7.0.  See [the conversation](https://github.com/rustprooflabs/pgosm-flex/issues/275#issuecomment-1340362190) for context.


When using replication you need to pin your process to a specific PgOSM Flex version
in the `docker run` command.  When upgrading to new versions,
be sure to check the release notes for manual upgrade steps for `--replication`.  
The release notes for
[PgOSM Flex 0.6.1](https://github.com/rustprooflabs/pgosm-flex/releases/tag/0.6.1)
are one example.
The notes discussed in the release notes have reference SQL scripts
under `db/data-migration` folder.  

----

**WARNING - Due to the ability to configure custom layersets these data-migration
scripts need manual review, and possibly manual adjustments for
your specific database and process.**

----


The other important change when using replication is to increase Postgres' `max_connections`.
See [this discussion on osm2pgsql](https://github.com/openstreetmap/osm2pgsql/discussions/1650)
for why this is necessary.

If using the Docker-internal Postgres instance this is done with `-c max_connections=300`
in the `docker run` command.  External database connections must update this
in the appropriate `postgresql.conf` file.


```bash
docker run --name pgosm -d --rm \
    -v ~/pgosm-data:/app/output \
    -v /etc/localtime:/etc/localtime:ro \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    -p 5433:5432 \
    -d rustprooflabs/pgosm-flex:0.7.0 \
        -c max_connections=300
```


Run the `docker exec` step with `--replication`.

```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia \
    --pgosm-date 2022-12-30 \
    --replication
```

Running the above command a second time will detect that the target database
has `osm2pgsql-replication` setup and load data via the defined replication
service.

> Note:  The `--pgosm-date` parameter is ignored during subsequent imports using `--replication`.



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
  --ram FLOAT               Amount of RAM in GB available on the machine
                            running the Docker container. This is used to
                            determine the appropriate osm2pgsql command via
                            osm2pgsql-tuner recommendation engine.  [required]
  --region TEXT             Region name matching the filename for data sourced
                            from Geofabrik. e.g. north-america/us. Optional
                            when --input-file is specified, otherwise
                            required.
  --subregion TEXT          Sub-region name matching the filename for data
                            sourced from Geofabrik. e.g. district-of-columbia
  --data-only               When set, skips running Sqitch and importing QGIS
                            Styles.
  --debug                   Enables additional log output
  --input-file TEXT         Set filename or absolute filepath to input osm.pbf
                            file. Overrides default file handling, archiving,
                            and MD5 checksum validation. Filename is assumed
                            under /app/output unless absolute path is used.
  --layerset TEXT           Layerset to load. Defines name of included
                            layerset unless --layerset-path is defined.
                            [required]
  --layerset-path TEXT      Custom path to load layerset INI from. Custom
                            paths should be mounted to Docker via docker run
                            -v ...
  --language TEXT           Set default language in loaded OpenStreetMap data
                            when available.  e.g. 'en' or 'kn'.
  --pg-dump                 Uses pg_dump after processing is completed to
                            enable easily load OpenStreetMap data into a
                            different database
  --pgosm-date TEXT         Date of the data in YYYY-MM-DD format. If today
                            (default), automatically downloads when files not
                            found locally. Set to historic date to load
                            locally archived PBF/MD5 file, will fail if both
                            files do not exist.
  --replication             EXPERIMENTAL - Replication mode enables updates
                            via osm2pgsql-replication.
  --schema-name TEXT        Change the final schema name, defaults to 'osm'.
  --skip-nested             When set, skips calculating nested admin polygons.
                            Can be time consuming on large regions.
  --srid TEXT               SRID for data loaded by osm2pgsql to PostGIS.
                            Defaults to 3857
  --sp-gist                 When set, builds SP-GIST indexes on geom column
                            instead of the default GIST indexes.
  --update [append|create]  EXPERIMENTAL - Wrap around osm2pgsql create v.
                            append modes, without using osm2pgsql-replication.
  --help                    Show this message and exit.
```

An example of running with many of the current options.

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
    --pg-dump \
    --skip-nested \
    --sp-gist \
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


## Skip nested place polygons

The nested place polygon calculation
([explained in this post](https://blog.rustprooflabs.com/2021/01/pgosm-flex-improved-openstreetmap-places-postgis))
adds minimal overhead to smaller regions, e.g. Colorado with a 225 MB PBF input file.
Larger regions, such as North America (12 GB PBF),
are impacted more severely as a difference in processing time.
Calculating nested place polygons for Colorado adds less than 30 seconds on an 8 minute process,
taking about 5% longer.
A larger region, such as North America, can take 33% longer adding more than
an hour and a half to the total processing time.
See [docs/PERFORMANCE.md](PERFORMANCE.md) for more details.


Use `--skip-nested` to bypass the calculation of nested admin polygons.


## Use `--pg-dump` to export data

> The `--pg-dump` option was added in 0.7.0.  Prior versions defaulted to using `pg_dump` and provided a `--skip-dump` option to override.  The default now is to only use `pg_dump` when requested.  See [#266](https://github.com/rustprooflabs/pgosm-flex/issues/266) for more.


A `.sql` file can be created using `pg_dump` as part of the processing
for easy loading into one or more external Postgres databases.
Add `--pg-dump` to the `docker exec` command to enable this feature.

The following example
creates an empty `myosm` database to load the processed and dumped OpenStreetMap
data.


```bash
psql -d postgres -c "CREATE DATABASE myosm;"
psql -d myosm -c "CREATE EXTENSION postgis;"

psql -d myosm \
    -f ~/pgosm-data/pgosm-flex-north-america-us-district-of-columbia-default-2023-01-21.sql
```

> The above assumes a database user with `superuser` permissions is used. See [docs/POSTGRES-PERMISSIONS.md](POSTGRES-PERMISSIONS.md) for a more granular approach to permissions.


## Configure Postgres inside Docker

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


