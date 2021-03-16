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

Each of these layer sets includes the core layer defintions
(see `style/*.lua`)
and post-processing SQL (see `sql/*.sql`).
The `.lua` scripts work with osm2pgsql's Flex output.
PgOSM-Flex is using these styles with a mix-and-match approach.
This is best illustrated by looking within the main `run-all.lua` script.
As the following shows, it does not define any actual styles, only includes
a single style, and runs another layer set (`run-no-tags`).


```lua
require "style.tags"
require "run-no-tags"
```

The `style.tags` script creates a table `osm.tags` that contains all OSM key/value
pairs, but with no geometry.  This is the largest table loaded by the `run-all`
layer set and enables joining any OSM data in another layer (e.g. `osm.road_line`)
to find any additional tags.


## Customize PgOSM

Track additional details in the `osm.pgosm_meta` table (see more below)
and customize behavior with the use of environment variables.

* `OSM_DATE`
* `PGOSM_SRID`
* `PGOSM_REGION`


To use `SRID 4326` instead of the default `SRID 3857`, set the `PGOSM_SRID`
environment variable before running osm2pgsql.

```bash
export PGOSM_SRID=4326
```

Changes to the SRID are reflected in output printed.

```bash
2021-01-08 15:01:15  osm2pgsql version 1.4.0 (1.4.0-72-gc3eb0fb6)
2021-01-08 15:01:15  Database version: 13.1 (Ubuntu 13.1-1.pgdg20.10+1)
2021-01-08 15:01:15  Node-cache: cache=800MB, maxblocks=12800*65536, allocation method=11
Custom SRID: 4326
...
```

----

## PgOSM via Docker

The easiest quick-start option to use PgOSM-Flex is with the
[Docker image](https://hub.docker.com/r/rustprooflabs/pgosm-flex).
The image has all the pre-reqs installs, handles downloading an OSM subregion
from Geofabrik, and saves a `.sql` file with the processed data to load into
your database(s).


Using `PGOSM_DATE` allows the Docker process to archive source PBF files
and easily reload them at a later date.

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

See [the full details in DOCKER-RUN.md](DOCKER-RUN.md).

----

## Standard Import

See [MANUAL-STEPS-RUN.md](MANUAL-STEPS-RUN.md) for prereqs and steps for
running without Docker.



## Points of Interest (POIs)


Loads an range of tags into a materialized view (`osm.poi_all`) for easy searching POIs.
Line and polygon data is forced to point geometry using
`ST_Centroid()`.  This layer duplicates a bunch of other more specific layers
(shop, amenity, etc.) to provide a single place for simplified POI searches.

Special layer included by layer sets `run-all` and `run-no-tags`.
See `style/poi.lua` for logic on how to include POIs.
The topic of POIs is subject and likely is not inclusive of everything that probably should be considered
a POI. If there are POIs missing
from this table please submit a [new issue](https://github.com/rustprooflabs/pgosm-flex/issues/new)
with sufficient details about what is missing.
Pull requests also welcome! [See CONTRIBUTING.md](CONTRIBUTING.md).



```sql
SELECT osm_type, COUNT(*) FROM osm.vpoi_all GROUP BY osm_type;
SELECT geom_type, COUNT(*) FROM osm.vpoi_all GROUP BY geom_type;
```



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


## One table to rule them all

From the perspective of database design, the `osm.unitable` option is the **worst**!

> This style included in PgOSM-Flex is intended to be used for troublshooting and quality control.  It is not intended to be used for real production workloads! This table is helpful for exploring the full data set when you don't really know what you are looking for, but you know **where** you are looking.

Load the `unitable.lua` script to make the full OpenStreetMap data set available in
one table. This violates all sorts of best practices established in this project
by shoving all features into a single unstructured table.


```bash
osm2pgsql --slim --drop \
    --output=flex --style=./unitable.lua \
    -d pgosm \
    ~/tmp/district-of-columbia-latest.osm.pbf
```

> The `unitable.lua` script include in in this project was [adapted from the unitable example from osm2pgsql](https://github.com/openstreetmap/osm2pgsql/blob/master/flex-config/unitable.lua). This version uses JSONB instead of HSTORE and takes advantage of `helpers.lua` to easily customize SRID.




## Additional resources

Blog posts covering various details and background information.

* [Better OpenStreetMap places in PostGIS](https://blog.rustprooflabs.com/2021/01/pgosm-flex-improved-openstreetmap-places-postgis)
* [Improved OpenStreetMap data structure in PostGIS](https://blog.rustprooflabs.com/2021/01/postgis-openstreetmap-flex-structure) 
* [Hands on with osm2pgsql's new Flex output](https://blog.rustprooflabs.com/2020/12/osm2gpsql-flex-output-to-postgis).


Use QGIS?  See [the README documenting using the QGIS styles](https://github.com/rustprooflabs/pgosm-flex/blob/main/db/qgis-style/README.md).

