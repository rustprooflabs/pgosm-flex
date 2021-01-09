# PgOSM Flex

The goal of PgOSM Flex is to provide high quality OpenStreetMap datasets in PostGIS
using the
[osm2pgsql Flex output](https://osm2pgsql.org/doc/manual.html#the-flex-output).
This project provides a curated set of Lua and SQL scripts to clean and organize
the most commonly used OpenStreetMap data, such as roads, buildings, and points of interest (POIs).

The overall approach is to do as much processing in the `<name>.lua` script
with post-processing steps creating indexes, constraints and comments in a companion `<name>.sql` script.
For more details on using this project see [Hands on with osm2pgsql's new Flex output](https://blog.rustprooflabs.com/2020/12/osm2gpsql-flex-output-to-postgis).

> Warning - The PgOSM Flex output is currently marked as experimental!  All testing done with osm2pgsql v1.4.0 or later.


## Project decisions

A few decisions made in this project:

* ID column is `osm_id`
* Geometry stored in SRID 3857
* Default to same units as OpenStreetMap (e.g. km/hr, meters)
* Data not deemed worthy of a dedicated column goes in side table `osm.tags`. Raw key/value data stored in `JSONB` column
* Points, Lines, and Polygons are not mixed in a single table

## Versions Supported

Requires Postgres 12+ and PostGIS 3.0.


## Deploy schema and load helper data

Deploying the table structure is done via [sqitch](https://sqitch.org/).

Assumes this repo is cloned under `~/git/pgosm-flex/` and a local Postgres
DB named `pgosm` has been created with the `postgis` extension installed.

```bash
cd ~/git/pgosm-flex/db
sqitch deploy db:pg:pgosm
```

**Optional** - Load helper road data.

```bash
cd ~/git/pgosm-flex/db
psql -d pgosm -f data/roads-us.sql
```


Currently only U.S. region drafted, more regions with local `maxspeed` are welcome via PR!


## Load main tables

The list of main tables in PgOSM-Flex will continue to grow.
The only layer intentionally excluded from the `run-all` script is `unitable.lua`.

```bash
osm2pgsql --slim --drop \
    --output=flex --style=./run-all.lua \
    -d pgosm \
    ~/tmp/district-of-columbia-latest.osm.pbf
```

Run matching SQL scripts.

```bash
psql -d pgosm -f ./run-all.sql
```

## Customize PgOSM

Some behavior can be customized at run time with the use of environment variables.
Current environment variables:

* `PGOSM_SRID`
* `PGOSM_SCHEMA`

> WARNING:  Customizing the schema name will cause the `.sql` scripts to break.

To use SRID 4326:

```bash
export PGOSM_SRID=4326
```

Changes reflected in output printed.

```bash
2021-01-08 15:01:15  osm2pgsql version 1.4.0 (1.4.0-72-gc3eb0fb6)
2021-01-08 15:01:15  Database version: 13.1 (Ubuntu 13.1-1.pgdg20.10+1)
2021-01-08 15:01:15  Node-cache: cache=800MB, maxblocks=12800*65536, allocation method=11
Custom SRID: 4326
Default Schema: osm
...
```


## Load main tables, No Tags

The `run-no-tags.lua` and `.sql` scripts run the same loads as the `run-all`,
just skipping the `osm.tags` table.  The `tags` table contains all OSM key/value
pairs with their `osm_id`.



```bash
osm2pgsql --slim --drop \
    --output=flex --style=./run-no-tags.lua \
    -d pgosm \
    ~/tmp/district-of-columbia-latest.osm.pbf
```

Matching SQL scripts.

```bash
psql -d pgosm -f ./run-no-tags.sql
```


## Load individual layer

A single layer can be added with commands such as this.  Each `.lua` script and matchi
`.sql` script is intended to be a standalone, or combined with others.

```bash
osm2pgsql --slim --drop \
    --output=flex --style=./road_major.lua \
    -d pgosm \
    ~/tmp/district-of-columbia-latest.osm.pbf
```

```bash
psql -d pgosm -f ./road_major.sql
```


## One table to rule them all

Load the `unitable.lua` script to make the full OpenStreetMap data set available in one 
table.  This violates all sorts of best practices established in this project by shoving all features into a single
unstructured table.  However, this table is helpful for exploring the full data set
when you don't really know what you are looking for, but you know **where** you are 
looking.  It is also helpful for exploring the full gambit of tags and geometries.

> The `unitable.lua` script include in PgOSM-Flex was [adapted from the example from osm2pgsql](https://github.com/openstreetmap/osm2pgsql/blob/master/flex-config/unitable.lua) to use JSONB instead of HSTORE and take advantage of `helpers.lua` to easily change SRID.

```bash
osm2pgsql --slim --drop \
    --output=flex --style=./unitable.lua \
    -d pgosm \
    ~/tmp/district-of-columbia-latest.osm.pbf
```

## Dump and reload data

To move data loaded on one Postgres instance to another, use `pg_dump`.

Create a directory to export.  Using `-Fd` for directory format to allow using
`pg_dump`/`pg_restore` with multiple processes (`-j 8`).  For the small data set for
Washington D.C. used here this isn't necessary, though can seriously speed up with larger areas, e.g. Europe or North America.

```bash
mkdir -p ~/tmp/osm_dc
pg_dump --no-owner --no-privileges --schema=osm \
    -d pgosm \
    -Fd -j 8 \
    -f ~/tmp/osm_dc
tar -cvf osm_dc.tar -C ~/tmp osm_dc
```

Move the `.tar`.  Untar and restore.

```bash
tar -xvf osm_eu.tar
pg_restore -j 8 -d pgosm_eu -Fd osm_eu/
```

## Quality Control

The process of selectively load specific features and not others always has the chance
of accidentally missing important data.

Running and examine tags from the SQL script `db/qc/features_not_in_run_all.sql`.
Run within `psql` (using `\i db/qc/features_not_in_run_all.sql`) or a GUI client
to explore the temp table used to return the aggregated results, `osm_missing`.
The table is a `TEMP TABLE` so will disappear when the session ends.

Example results from initial run (v0.0.4) showed some obvious omissions from the
current layer definitions.

```bash
┌────────────────────────────────────────┬────────┐
│           jsonb_object_keys            │ count  │
╞════════════════════════════════════════╪════════╡
│ landuse                                │ 110965 │
│ addr:street                            │  89482 │
│ addr:housenumber                       │  89210 │
│ name                                   │  47151 │
│ leisure                                │  25351 │
│ addr:state                             │  19051 │
│ power                                  │  16933 │
│ addr:unit                              │  13973 │
│ building:part                          │  13773 │
│ golf                                   │  13427 │
│ railway                                │  13032 │
│ addr:city                              │  12426 │
│ addr:postcode                          │  12358 │
│ height                                 │  12113 │
│ building:colour                        │  11124 │
│ roof:colour                            │  11115 │
```

## Adding new feature layers

Checklist for feature layers:

* Create `<feature>.lua`
* Create `<feature>.sql`
* Update `run-no-tags.lua`
* Update `run-no-tags.sql`
* Update `db/qc/features_not_in_run_all.sql`

