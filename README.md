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


## Layer Sets

Layer sets are defined under the directory [pgosm-flex/flex-config/](https://github.com/rustprooflabs/pgosm-flex/tree/main/flex-config), the current `run-*` options are:

* `run-all`
* `run-no-tags`
* `run-road-place`
* `run-unitable`


----

## PgOSM via Docker

The easiest quick-start option to use PgOSM-Flex is with the
[Docker image](https://hub.docker.com/r/rustprooflabs/pgosm-flex).
The image has all the pre-reqs installs, handles downloading an OSM subregion
from Geofabrik, and saves a `.sql` file with the processed data to load into
your database(s).


### Basic Docker usage

This section outlines the basic operations for using Docker to run PgOSM-Flex.
See [the full details in DOCKER-RUN.md](DOCKER-RUN.md). 

Create directory for the `.osm.pbf` file and output `.sql` file.

```bash
mkdir ~/pgosm-data
```

Start the `pgosm` Docker container to make PostgreSQL / PostGIS available and prepare
to run the PgOSM-Flex script.


```bash
docker run --name pgosm -d \
    -v ~/pgosm-data:/app/output \
    -v /etc/localtime:/etc/localtime:ro \
    -e POSTGRES_PASSWORD=mysecretpassword \
    -p 5433:5432 -d rustprooflabs/pgosm-flex
```

----

**The Postgres instance is not immediately ready for connections.  Wait a few seconds before running the following `docker exec` command.**

----

Run the processing for the Washington D.C. sub-region.  This small sub-region is great
for testing, it runs fast even on the smallest hardware.

```bash
docker exec -it \
    -e POSTGRES_PASSWORD=mysecretpassword -e POSTGRES_USER=postgres \
    pgosm bash docker/run_pgosm_flex.sh \
    north-america/us \
    district-of-columbia \
    500 \
    run-all
```

The command  `bash docker/run_pgosm_flex.sh` handles the steps required to download,
process and export OpenStreetMap data in plain `.sql`. The data is available in the
running `pgosm` container (`psql -h localhost -p 5433 -d pgosm`) but designed intent
is to load the data into your PostGIS database(s).

The script uses a region (`north-america/us`) and sub-region (`district-of-columbia`) that must match values in URLs from the Geofabrik download server.  The osm2pgsql cache is set (`2000`) and the PgOSM-Flex layer set is defined (`run-all`).


----

## Standard Import

See [MANUAL-STEPS-RUN.md](MANUAL-STEPS-RUN.md) for prereqs and steps for
running without Docker.



## (Optional) Calculate Nested place polygons

Nested places refers to administrative boundaries that are contained, or contain,
other administrative boundaries. An example of this is the State of Colorado
contains the boundary for Jefferson County, Colorado.

See [Better OpenStreetMap places in PostGIS](https://blog.rustprooflabs.com/2021/01/pgosm-flex-improved-openstreetmap-places-postgis)
for more.


```sql
CALL osm.build_nested_admin_polygons();
```

Example record showing the nesting calculated.

```sql
SELECT osm_id, name, osm_type, admin_level, nest_level,
        name_path, osm_id_path, admin_level_path,
        innermost
    FROM osm.place_polygon_nested
    WHERE name = 'Shepherd Park'
;
```

```bash
Name            |Value                                          |
----------------|-----------------------------------------------|
osm_id          |-4603194                                       |
name            |Shepherd Park                                  |
osm_type        |suburb                                         |
admin_level     |10                                             |
nest_level      |3                                              |
name_path       |{District of Columbia,Washington,Shepherd Park}|
osm_id_path     |{-162069,-5396194,-4603194}                    |
admin_level_path|{4,6,10}                                       |
innermost       |true                                           |
```


## Explore data loaded

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

