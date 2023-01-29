# Quick Start



See the [Docker Usage](#docker-usage) section below for an explanation of
these commands.

```bash
mkdir ~/pgosm-data
export POSTGRES_USER=postgres
export POSTGRES_PASSWORD=mysecretpassword

docker run --name pgosm -d --rm \
    -v ~/pgosm-data:/app/output \
    -v /etc/localtime:/etc/localtime:ro \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    -p 5433:5432 -d rustprooflabs/pgosm-flex

docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia
```



## PgOSM via Docker

The PgOSM Flex
[Docker image](https://hub.docker.com/r/rustprooflabs/pgosm-flex)
is hosted on Docker Hub.
The image includes all the pre-requisite software and handles all of the options,
logic, an post-processing steps required.  Features include:

* Automatic data download from Geofabrik and validation against checksum
* Custom Flex layers built in Lua
* Mix and match layers using Layersets
* Loads to Docker-internal Postgres, or externally defined Postgres
* Supports `osm2pgsql-replication` and `osm2pgsql --append` mode
* Export processed data via `pg_dump` for loading into additional databases


## Docker usage

This section outlines a typical import using Docker to run PgOSM Flex.
See the full Docker instructions in [docs/DOCKER-RUN.md](docs/DOCKER-RUN.md).

Create directory for the `.osm.pbf` file, output `.sql` file, log output, and
the osm2pgsql command ran.


```bash
mkdir ~/pgosm-data
```

Set environment variables for the temporary Postgres connection in Docker.
These are required for the Docker container to run.


```bash
export POSTGRES_USER=postgres
export POSTGRES_PASSWORD=mysecretpassword
```

Start the `pgosm` Docker container. At this point, Postgres / PostGIS
is available on port `5433`.

```bash
docker run --name pgosm -d --rm \
    -v ~/pgosm-data:/app/output \
    -v /etc/localtime:/etc/localtime:ro \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    -p 5433:5432 -d rustprooflabs/pgosm-flex
```

Use `docker exec` to run the processing for the Washington D.C subregion.
This example uses three (3) parameters to specify the total system RAM (8 GB)
along with a region/subregion.

* Total RAM for osm2pgsql, Postgres and OS (`8`)
* Region (`north-america/us`)
* Sub-region (`district-of-columbia`) (Optional)


```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia
```


The above command takes roughly 1 minute to run if the PBF for today
has already been downloaded.
If the PBF is not downloaded it will depend on how long
it takes to download the 17 MB PBF file + ~ 1 minute processing.


## After processing

The processed OpenStreetMap data is also available in the Docker container on port `5433`.
You can connect and query directly in the Docker container.

```bash
psql -h localhost -p 5433 -d pgosm -U postgres -c "SELECT COUNT(*) FROM osm.road_line;"

┌───────┐
│ count │
╞═══════╡
│ 39865 │
└───────┘
```


The `~/pgosm-data` directory has two (2) files from a typical single run.
The PBF file and its MD5 checksum have been renamed with the date in the filename.
This enables loading the file downloaded today 
again in the future, either with the same version of PgOSM Flex or the latest version. The `docker exec` command uses the `PGOSM_DATE` environment variable
to load these historic files.


If `--pg-dump` option is used the output `.sql` is also saved in
the `~/pgosm-data` directory.
This `.sql` file can be loaded into any other database with PostGIS and the proper
permissions.


```bash
ls -alh ~/pgosm-data/

-rw-r--r-- 1 root     root      18M Jan 21 03:45 district-of-columbia-2023-01-21.osm.pbf
-rw-r--r-- 1 root     root       70 Jan 21 04:39 district-of-columbia-2023-01-21.osm.pbf.md5
-rw-r--r-- 1 root     root     163M Jan 21 16:14 north-america-us-district-of-columbia-default-2023-01-21.sql
```



## Meta table

PgOSM Flex tracks processing metadata in the ``osm.pgosm_flex``  table. The initial import
has `osm2pgsql_mode = 'create'`, the subsequent update has
`osm2pgsql_mode = 'append'`. 


```sql
SELECT osm_date, region, srid,
        pgosm_flex_version, osm2pgsql_version, osm2pgsql_mode
    FROM osm.pgosm_flex
;
```

```bash
┌────────────┬───────────────────────────┬──────┬────────────────────┬───────────────────┬────────────────┐
│  osm_date  │          region           │ srid │ pgosm_flex_version │ osm2pgsql_version │ osm2pgsql_mode │
╞════════════╪═══════════════════════════╪══════╪════════════════════╪═══════════════════╪════════════════╡
│ 2022-11-04 │ north-america/us-colorado │ 3857 │ 0.6.2-e1f140f      │ 1.7.2             │ create         │
│ 2022-11-25 │ north-america/us-colorado │ 3857 │ 0.6.2-e1f140f      │ 1.7.2             │ append         │
└────────────┴───────────────────────────┴──────┴────────────────────┴───────────────────┴────────────────┘
```
