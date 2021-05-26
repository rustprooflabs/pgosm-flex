# PgOSM Flex

The goal of PgOSM Flex is to provide high quality OpenStreetMap datasets in PostGIS
using the
[osm2pgsql Flex output](https://osm2pgsql.org/doc/manual.html#the-flex-output).
This project provides a curated set of Lua and SQL scripts to clean and organize
the most commonly used OpenStreetMap data, such as roads, buildings, and points of interest (POIs).

The approach to processing is to do as much processing in the `<name>.lua` script
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
* osm2pgsql 1.4.2+ --> commit 94dae34 or newer


### :warning: Breaking change

The osm2pgsql project added built-in JSON support after the tagged
v1.4.2 release.  This change ([commit](https://github.com/openstreetmap/osm2pgsql/commit/94dae34b7aa1463339cdb6768d28a6e8ee53ef65))
is not yet in a tagged release of osm2pgsql, only the
latest `master` branch.

This is only a concern when running on a server where you install osm2pgsql
from a package manager. Following the instructions in
[MANUAL-STEPS-RUN.md](MANUAL-STEPS-RUN.md) installs the latest
version of osm2pgsql from source and avoids this issue.
Also, using the PgOSM Flex Docker image makes this a non-issue.


## PgOSM via Docker

The easiest option to use PgOSM-Flex is with the
[Docker image](https://hub.docker.com/r/rustprooflabs/pgosm-flex).
The image has all the pre-reqs installed, handles downloading an OSM subregion
from Geofabrik, and saves an output `.sql` file with the processed data
ready to load into your database(s).

The script in the Docker image uses `PGOSM_DATE` to enable the Docker process
to archive source PBF files and easily reload them at a later date.


### Basic Docker usage

This section outlines the basic operations for using Docker to run PgOSM-Flex.
See [the full Docker instructions in DOCKER-RUN.md](DOCKER-RUN.md).

Create directory for the `.osm.pbf` file, output `.sql` file, log output, and
the osm2pgsql command ran.


```bash
mkdir ~/pgosm-data
```

Start the `pgosm` Docker container. At this point, PostgreSQL / PostGIS
is available on port `5433`.

```bash
docker run --name pgosm -d \
    -v ~/pgosm-data:/app/output \
    -v /etc/localtime:/etc/localtime:ro \
    -e POSTGRES_PASSWORD=mysecretpassword \
    -p 5433:5432 -d rustprooflabs/pgosm-flex
```

Run the processing for the Washington D.C.  The `run_pgosm_flex.sh` script
requires four (4) parameters:

* Region (`north-america/us`)
* Sub-region (`district-of-columbia`)
* Total RAM for osm2pgsql, Postgres and OS (`8`)
* PgOSM-Flex layer set (`run-all`)


```bash
docker exec -it \
    -e POSTGRES_PASSWORD=mysecretpassword \
    -e POSTGRES_USER=postgres \
    pgosm bash docker/run_pgosm_flex.sh \
    north-america/us \
    district-of-columbia \
    8 \
    run-all
```

The initial output with the `docker exec` command points to the log file
(linked in the `docker run` command above), monitor this file to track
progress of the import.


```bash
Monitor /app/output/district-of-columbia.log for progress...
If paths setup as outlined in README.md, use:
    tail -f ~/pgosm-data/district-of-columbia.log
```


### After processing

After the `docker exec` command completes, the processed OpenStreetMap
data is available in the Docker container on port `5433` and has automatically
been exported to `~/pgosm-data/pgosm-flex-district-of-columbia-run-all.sql`.


Connect and query directly in the Docker container.

```bash
psql -h localhost -p 5433 -d pgosm -U postgres -c "SELECT COUNT(*) FROM osm.road_line;"

┌───────┐
│ count │
╞═══════╡
│ 38480 │
└───────┘
```

Or load the processed data (now in `.sql` format) to the Postgres/PostGIS instance of your choice.

```bash
psql -d $YOUR_DB_STRING \
    -f ~/pgosm-data/pgosm-flex-district-of-columbia-run-all.sql
```



The `~/pgosm-data` directory has four (4) files, the PBF and its MD5 chcksum,
the processing log, and the processed output file (`.sql`).


```bash
ls -alh ~/pgosm-data/

-rw-r--r--  1 root        root         17M May 18 17:24 district-of-columbia-2021-05-18.osm.pbf
-rw-r--r--  1 root        root          70 May 18 17:24 district-of-columbia-2021-05-18.osm.pbf.md5
-rw-r--r--  1 root        root        799K May 18 17:25 district-of-columbia.log
-rw-r--r--  1 root        root         117 May 18 17:24 osm2pgsql-district-of-columbia.sh
-rw-r--r--  1 root        root        154M May 18 17:25 pgosm-flex-district-of-columbia-run-all.sql
```

The designed intent is to load the OpenStreetMap data processed by this
Docker image into your PostGIS database(s).
The process runs `pg_dump` on the resulting
data to create the `.sql` output file.  This can be easily loaded into any
Postgres/PostGIS database using `psql`.


```bash
psql -d $YOUR_DB_STRING \
    -f ~/pgosm-data/pgosm-flex-district-of-columbia-run-all.sql
```


The source file (`.osm.pbf`)
and its MD5 verificiation file (`osm.pbf.md5`) get renamed from `-latest`
to the date (`-2021-05-18`).  This enables loading the file downloaded today 
again in the future, either with the same version of PgOSM Flex or the latest version. The `docker exec` command uses the `PGOSM_DATE` environment variable
to load these historic files.

See [more in DOCKER-RUN.md](DOCKER-RUN.md).


----

## On-server import

See [MANUAL-STEPS-RUN.md](MANUAL-STEPS-RUN.md) for prereqs and steps for
running without Docker.

----



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
* `PGOSM_LANGUAGE`


### Custom SRID

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

### Preferred Language

The `name` column throughout PgOSM-Flex defaults to using the highest priority
name tag according to the [OSM Wiki](https://wiki.openstreetmap.org/wiki/Names). Setting `PGOSM_LANGUAGE` allows giving preference to name tags with the
given language.
The value of `PGOSM_LANGUAGE` should match the codes used by OSM:

> where code is a lowercase language's ISO 639-1 alpha2 code, or a lowercase ISO 639-2 code if an ISO 639-1 code doesn't exist." -- [Multilingual names on OSM Wiki](https://wiki.openstreetmap.org/wiki/Multilingual_names)


```bash
export PGOSM_LANGUAGE=kn
```




## QGIS Layer Styles

Use QGIS to visualize OpenStreetMap data? This project includes a few basic
styles using the `public.layer_styles` table created by QGIS.

See [the QGIS Style README.md](https://github.com/rustprooflabs/pgosm-flex/blob/main/db/qgis-style/README.md)
for more information.


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


Counts of POIs by `osm_type`.

```sql
SELECT osm_type, COUNT(*)
    FROM osm.vpoi_all
    GROUP BY osm_type
    ORDER BY COUNT(*) DESC;
```

Results from Washington D.C. subregion (March 2020).

```
┌──────────┬───────┐
│ osm_type │ count │
╞══════════╪═══════╡
│ amenity  │ 12663 │
│ leisure  │  2701 │
│ building │  2045 │
│ shop     │  1739 │
│ tourism  │   729 │
│ man_made │   570 │
│ landuse  │    32 │
│ natural  │    19 │
└──────────┴───────┘
```

Includes Points (`N`), Lines (`L`) and Polygons (`W`).


```sql
SELECT geom_type, COUNT(*) 
    FROM osm.vpoi_all
    GROUP BY geom_type
    ORDER BY COUNT(*) DESC;
```

```
┌───────────┬───────┐
│ geom_type │ count │
╞═══════════╪═══════╡
│ W         │ 10740 │
│ N         │  9556 │
│ L         │   202 │
└───────────┴───────┘
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


## JSONB support

PgOSM-Flex uses `JSONB` in Postgres to store the raw OpenSteetMap
key/value data (`tags` column)
and relation members (`member_ids`).

Current `JSONB` columns:

* `osm.tags.tags`
* `osm.unitable.tags`
* `osm.place_polygon.member_ids`
* `osm.vplace_polygon.member_ids`
* `osm.poi_polygon.member_ids`


## Additional resources

Blog posts covering various details and background information.

* [Better OpenStreetMap places in PostGIS](https://blog.rustprooflabs.com/2021/01/pgosm-flex-improved-openstreetmap-places-postgis)
* [Improved OpenStreetMap data structure in PostGIS](https://blog.rustprooflabs.com/2021/01/postgis-openstreetmap-flex-structure) 
* [Hands on with osm2pgsql's new Flex output](https://blog.rustprooflabs.com/2020/12/osm2gpsql-flex-output-to-postgis).

