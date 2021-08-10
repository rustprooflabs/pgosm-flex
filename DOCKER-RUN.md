# Using PgOSM-Flex within Docker

This README provides details about running PgOSM-Flex using the image defined
in `Dockerfile` and the script loaded from `docker/pgosm_flex.py`.


## Setup and Run Container

Create directory for the `.osm.pbf` file and output `.sql` file.

```bash
mkdir ~/pgosm-data
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
    -e POSTGRES_PASSWORD=mysecretpassword \
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
    -e POSTGRES_PASSWORD=mysecretpassword -e POSTGRES_USER=postgres \
    pgosm python3 docker/pgosm_flex.py \
    --layerset=run-all --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia
```


## Customize PgOSM-Flex

The following command sets the four (4) main env vars used to customize PgOSM-Flex.

* `PGOSM_SRID` - Set custom SRID, must be in `public.spatial_ref_sys`.  Default `3857`
* `PGOSM_DATA_SCHEMA_NAME` - Final schema name for the OpenStreetMap data. Default `osm`
* `PGOSM_DATA_SCHEMA_ONLY` - When `false` (default) the QGIS styles and `pgosm` schema are exported along with the `PGOSM_DATA_SCHEMA_NAME` schema
* `PGOSM_DATE` - Used to document data loaded to DB in `osm.pgosm_flex.pgosm_date`, and for archiving PBF/MD5 files.  Defaults to today.
* `PGOSM_LANGUAGE` - Used to prefer specific language when it exists.


```bash
docker exec -it \
    -e POSTGRES_PASSWORD=mysecretpassword -e POSTGRES_USER=postgres \
    -e PGOSM_SRID=4326 \
    -e PGOSM_DATA_SCHEMA_ONLY=true \
    -e PGOSM_DATA_SCHEMA_NAME=osm_dc \
    -e PGOSM_DATE='2021-03-11' \
    -e PGOSM_LANGUAGE=en \
    pgosm python3 docker/pgosm_flex.py \
    north-america/us \
    district-of-columbia \
    8 \
    run-all
```

## Skip nested polygon calculation

The default is to run the nested polygon calculation. This can take considerable time on larger regions or may
be otherwise unwanted.  Define the env var `PGOSM_SKIP_NESTED_POLYGON` with the `docker exec` command
to skip this process.

```bash
 -e PGOSM_SKIP_NESTED_POLYGON=anything
```


## Always download

To force the processing to remove existing files and re-download the latest PBF and MD5 files from Geofabrik, set the `PGOSM_ALWAYS_DOWNLOAD` env var when running the Docker container.

```bash
docker run --name pgosm -d --rm \
    -v ~/pgosm-data:/app/output \
    -e POSTGRES_PASSWORD=mysecretpassword \
    -e PGOSM_ALWAYS_DOWNLOAD=1 \
    -p 5433:5432 -d rustprooflabs/pgosm
```

## Configure Postgres in Docker

Add customizations with the `-c` switch, e.g. `-c shared_buffers=1GB`,
to customize Postgres' configuration at run-time in Docker.



```bash
docker run --name pgosm -d --rm \
    -v ~/pgosm-data:/app/output \
    -v /etc/localtime:/etc/localtime:ro \
    -e POSTGRES_PASSWORD=mysecretpassword \
    -p 5433:5432 -d rustprooflabs/pgosm-flex \
    -c shared_buffers=1GB \
    -c maintenance_work_mem=1GB \
    -c checkpoint_timeout=300min \
    -c max_wal_senders=0 -c wal_level=minimal \
    -c checkpoint_completion_target=0.9 \
    -c random_page_cost=1.0
```



