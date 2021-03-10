# PgOSM Flex

The goal of PgOSM Flex is to provide high quality OpenStreetMap datasets in PostGIS
using the
[osm2pgsql Flex output](https://osm2pgsql.org/doc/manual.html#the-flex-output).
This project provides a curated set of Lua and SQL scripts to clean and organize
the most commonly used OpenStreetMap data, such as roads, buildings, and points of interest (POIs).

The overall approach is to do as much processing in the `<name>.lua` script
with post-processing steps creating indexes, constraints and comments in a companion `<name>.sql` script.


> Note: While osm2pgsql is still marked as experimental, this project is already being used to support production workloads.


## Project decisions

A few decisions made in this project:

* ID column is `osm_id`
* Geometry stored in SRID 3857
* Geometry column named `geom`
* Default to same units as OpenStreetMap (e.g. km/hr, meters)
* Data not deemed worthy of a dedicated column goes in side table `osm.tags`. Raw key/value data stored in `JSONB` column
* Points, Lines, and Polygons are not mixed in a single table


## Versions Supported

Minimum versions supported:

* Postgres 12
* PostGIS 3.0
* osm2pgsql 1.4.0

----

## PgOSM via Docker

The easiest quick-start option to use PgOSM-Flex is with the Docker image.
See the Docker image on [Docker Hub for instructions](https://hub.docker.com/r/rustprooflabs/pgosm-flex).


----


## Standard Import

These instructions show how to manually run the PgOSM-Flex process.
This is the best option for scaling to larger regions (North America, Europe, etc.)
due to the need to customize a number of configurations.  Review the
`docker/run_pgosm_flex.sh` for a starting point to automating the process.

This basic working example uses Washington D.C. for a small, fast test of the
process.

> Loading the full data set with `run-all` as shown here results in a lot of data.  See [the instructions in LOAD-DATA.md](LOAD-DATA.md) for more ways to use and customize PgOSM-Flex.

### Pre-reqs

Install prereqs as user with sudo.  Example for Ubuntu 20.04.

```bash
sudo apt update
sudo apt install -y --no-install-recommends \
        sqitch wget ca-certificates \
        git make cmake g++ \
        libboost-dev libboost-system-dev \
        libboost-filesystem-dev libexpat1-dev zlib1g-dev \
        libbz2-dev libpq-dev libproj-dev lua5.2 liblua5.2-dev \
        lua-dkjson
```

Install osm2pgsql from source.

```bash
git clone git://github.com/openstreetmap/osm2pgsql.git
mkdir osm2pgsql/build
cd osm2pgsql/build
cmake ..
make
sudo make install
```


### Prepare data / database


Download the PBF file and MD5 from Geofabrik, verify integrity.  The output
from the `md5sum` command should always match the contents of the `.md5` file.

```bash
mkdir ~/tmp
cd ~/tmp
wget https://download.geofabrik.de/north-america/us/district-of-columbia-latest.osm.pbf
wget https://download.geofabrik.de/north-america/us/district-of-columbia-latest.osm.pbf.md5

cat ~/tmp/district-of-columbia-latest.osm.pbf.md5
md5sum ~/tmp/district-of-columbia-latest.osm.pbf
```

Prepare the `pgosm` database in Postgres.
Need to create the `postgis` extension and the `osm` schema.

```bash
psql -c "CREATE DATABASE pgosm;"
psql -d pgosm -c "CREATE EXTENSION postgis; CREATE SCHEMA osm;"
```


### Run osm2pgsql w/ PgOSM-Flex

The PgOSM-Flex styles from this project are required to run the following.
Clone the repo and change into the directory containing
the `.lua` and `.sql` scripts.


```bash
mkdir ~/git
cd ~/git
git clone https://github.com/rustprooflabs/pgosm-flex.git
cd pgosm-flex/flex-config
```

(Optional) Set the `PGOSM_DATE` env var to indicate the date the OpenStreetMap
data was sourced.  This is most helpful when the PBF file was saved
more than a couple days ago to indicate to users of the data when the data was from.  The default is to use the current date.

```bash
export PGOSM_DATE='2021-01-27'
```

The date is in the `osm.pgosm_flex` table.

```sql
SELECT osm_date FROM osm.pgosm_flex;
```

```bash
osm_date  |
----------|
2021-01-27|
```



The `run-all.lua` script provides the most complete set of OpenStreetMap
data.  The list of main tables in PgOSM-Flex will continue to grow and evolve.
See [LOAD-DATA.md](LOAD-DATA.md) for more about loading data.


```bash
cd pgosm-flex/flex-config

osm2pgsql --slim --drop \
    --output=flex --style=./run-all.lua \
    -d pgosm \
    ~/tmp/district-of-columbia-latest.osm.pbf
```

After osm2pgsql completes the main load, run the matching SQL scripts. 
Each `.lua` has a matching `.sql` to create primary keys, indexes, comments,
views and more.

```bash
psql -d pgosm -f ./run-all.sql
```

> Note: The `run-all` scripts exclude `unitable` and `road_major`.


### Explore data loaded

A peek at some of the tables loaded.
This query requires the
[PostgreSQL Data Dictionary (PgDD) extension](https://github.com/rustprooflabs/pgdd),
use `\dt+ osm.*` in `psql` for similar details.


```sql
SELECT s_name, t_name, rows, size_plus_indexes 
    FROM dd.tables 
    WHERE s_name = 'osm' 
    ORDER BY t_name LIMIT 10;
```

```bash
    ┌────────┬──────────────────────┬────────┬───────────────────┐
    │ s_name │        t_name        │  rows  │ size_plus_indexes │
    ╞════════╪══════════════════════╪════════╪═══════════════════╡
    │ osm    │ amenity_line         │      7 │ 56 kB             │
    │ osm    │ amenity_point        │   5796 │ 1136 kB           │
    │ osm    │ amenity_polygon      │   7593 │ 3704 kB           │
    │ osm    │ building_point       │    525 │ 128 kB            │
    │ osm    │ building_polygon     │ 161256 │ 55 MB             │
    │ osm    │ indoor_line          │      1 │ 40 kB             │
    │ osm    │ indoor_point         │      5 │ 40 kB             │
    │ osm    │ indoor_polygon       │    288 │ 136 kB            │
    │ osm    │ infrastructure_point │    884 │ 216 kB            │
    │ osm    │ landuse_point        │     18 │ 56 kB             │
    └────────┴──────────────────────┴────────┴───────────────────┘
```



## Meta table

PgOSM-Flex tracks basic metadata in table ``osm.pgosm_flex``.
The `ts` is set by the post-processing script.  It does not necessarily
indicate the date of the data loaded, though in general it should be close
depending on your processing pipeline.


```sql
SELECT *
    FROM osm.pgosm_flex;
```

```bash
┌────────────┬──────────────┬───────────────┬────────────────────┬──────┬───────────────────────────────────┬───────────────────┐
│  osm_date  │ default_date │    region     │ pgosm_flex_version │ srid │            project_url            │ osm2pgsql_version │
╞════════════╪══════════════╪═══════════════╪════════════════════╪══════╪═══════════════════════════════════╪═══════════════════╡
│ 2020-01-01 │ t            │ north-america │ 0.1.1-f488d7b      │ 3857 │ https://github.com/rustprooflabs/…│ 1.4.1             │
│            │              │               │                    │      │…pgosm-flex                        │                   │
└────────────┴──────────────┴───────────────┴────────────────────┴──────┴───────────────────────────────────┴───────────────────┘
```


## Query examples

For example queries with data loaded by PgOSM-Flex see
[QUERY.md](QUERY.md).



## Additional structure and helper data

**Optional**

Deploying the additional table structure is done via [sqitch](https://sqitch.org/).

Assumes this repo is cloned under `~/git/pgosm-flex/` and a local Postgres
DB named `pgosm` has been created with the `postgis` extension installed.

```bash
cd ~/git/pgosm-flex/db
sqitch deploy db:pg:pgosm
```

With the structures created, load helper road data.

```bash
cd ~/git/pgosm-flex/db
psql -d pgosm -f data/roads-us.sql
```


Currently only U.S. region drafted, more regions with local `maxspeed` are welcome via PR!



## Additional resources

Blog posts covering various details and background information.

* [Better OpenStreetMap places in PostGIS](https://blog.rustprooflabs.com/2021/01/pgosm-flex-improved-openstreetmap-places-postgis)
* [Improved OpenStreetMap data structure in PostGIS](https://blog.rustprooflabs.com/2021/01/postgis-openstreetmap-flex-structure) 
* [Hands on with osm2pgsql's new Flex output](https://blog.rustprooflabs.com/2020/12/osm2gpsql-flex-output-to-postgis).


Use QGIS?  See [the README documenting using the QGIS styles](https://github.com/rustprooflabs/pgosm-flex/blob/main/db/qgis-style/README.md).

