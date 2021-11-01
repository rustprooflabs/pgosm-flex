# PgOSM Flex

The goal of PgOSM Flex is to provide high quality OpenStreetMap datasets in PostGIS
using the
[osm2pgsql Flex output](https://osm2pgsql.org/doc/manual.html#the-flex-output).
This project provides a curated set of Lua and SQL scripts to clean and organize
the most commonly used OpenStreetMap data, such as roads, buildings, and points of interest (POIs).

The approach to processing is to do as much processing in the `<name>.lua` script
with post-processing steps creating indexes, constraints and comments in a companion `<name>.sql` script.


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
* osm2pgsql 1.5.0


## PgOSM via Docker

The easiest option to use PgOSM-Flex is with the
[Docker image](https://hub.docker.com/r/rustprooflabs/pgosm-flex).
The image has all the pre-reqs installed, handles downloading an OSM subregion
from Geofabrik, and saves an output `.sql` file with the processed data
ready to load into your database(s).
The PBF/MD5 source files are archived by date with the ability to
easily reload them at a later date.


### Basic Docker usage

This section outlines the basic operations for using Docker to run PgOSM-Flex.
See [the full Docker instructions in docs/DOCKER-RUN.md](docs/DOCKER-RUN.md).

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

Start the `pgosm` Docker container. At this point, PostgreSQL / PostGIS
is available on port `5433`.

```bash
docker run --name pgosm -d --rm \
    -v ~/pgosm-data:/app/output \
    -v /etc/localtime:/etc/localtime:ro \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    -p 5433:5432 -d rustprooflabs/pgosm-flex
```

Run the processing for the Washington D.C.  The `docker/pgosm_flex.py` script
requires two (2) parameters, typical use will use three (3) to include
the `--subregion`.


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

The initial output with the `docker exec` command points to the log file
(linked in the `docker run` command above), monitor this file to track
progress of the import.

```bash
Monitor /app/output/district-of-columbia.log for progress...
If paths setup as outlined in README.md, use:
    tail -f ~/pgosm-data/district-of-columbia.log
```

The above command takes roughly 1 minute to run if the PBF for today
has already been downloaded.
If the PBF is not downloaded it will depend on how long
it takes to download the 17 MB PBF file + ~ 1 minute processing.

The output `.sql` file is saved under
`~/pgosm_data/pgosm-flex-north-america-us-district-of-columbia-run-all.sql`.
This `.sql` file can be loaded into a PostGIS enabled database
using:

```bash
psql -d postgres -c "CREATE DATABASE myosm;"
psql -d myosm -c "CREATE EXTENSION postgis;"
```

```bash
psql -d myosm \
    -f ~/pgosm-data/pgosm-flex-north-america-us-district-of-columbia-run-all.sql
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
-rw-r--r--  1 root        root        154M May 18 17:25 pgosm-flex-north-america-us-district-of-columbia-run-all.sql
```

The designed intent is to load the OpenStreetMap data processed by this
Docker image into your PostGIS database(s).
The process runs `pg_dump` on the resulting
data to create the `.sql` output file.  This can be easily loaded into any
Postgres/PostGIS database using `psql`.


```bash
psql -d $YOUR_DB_STRING \
    -f ~/pgosm-data/pgosm-flex-north-america-us-district-of-columbia-run-all.sql
```


The source file (`.osm.pbf`)
and its MD5 verificiation file (`osm.pbf.md5`) get renamed from `-latest`
to the date (`-2021-05-18`).  This enables loading the file downloaded today 
again in the future, either with the same version of PgOSM Flex or the latest version. The `docker exec` command uses the `PGOSM_DATE` environment variable
to load these historic files.

See [more in docs/DOCKER-RUN.md](docs/DOCKER-RUN.md).


----

## On-server import

See [docs/MANUAL-STEPS-RUN.md](docs/MANUAL-STEPS-RUN.md) for prereqs and steps for
running without Docker.

----



## Layer Sets


PgOSM Flex includes a few layersets and makes it easy to customize your own.
See [docs/LAYERSETS.md](docs/LAYERSETS.md) for details.




## QGIS Layer Styles

Use QGIS to visualize OpenStreetMap data? This project includes a few basic
styles using the `public.layer_styles` table created by QGIS.

See [the QGIS Style README.md](https://github.com/rustprooflabs/pgosm-flex/blob/main/db/qgis-style/README.md)
for more information.

Loaded by Docker process by default.  Is excluded when `--data-only` used.



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
[docs/QUERY.md](docs/QUERY.md).


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

See the listing of known
[projects using PgOSM Flex](docs/PROJECTS.md).


Blog posts covering various details and background information.

* [Better OpenStreetMap places in PostGIS](https://blog.rustprooflabs.com/2021/01/pgosm-flex-improved-openstreetmap-places-postgis)
* [Improved OpenStreetMap data structure in PostGIS](https://blog.rustprooflabs.com/2021/01/postgis-openstreetmap-flex-structure) 
* [Hands on with osm2pgsql's new Flex output](https://blog.rustprooflabs.com/2020/12/osm2gpsql-flex-output-to-postgis).
