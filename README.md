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



## Load main tables

The list of "main" tables will continue to grow.  This will evolve as more layers are added.
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


## Load individual layers

Individual layers can be added with commands such as this.

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

Load the `unitable.lua` script to make the full OpenStreetMap data set available in one table.  This could be helpful for exploring the data when you don't really know what you are
looking for.

Adapted from https://github.com/openstreetmap/osm2pgsql/blob/master/flex-config/unitable.lua
to use JSONB instead of HSTORE.

```bash
osm2pgsql --slim --drop \
    --output=flex --style=./unitable.lua \
    -d pgosm \
    ~/tmp/district-of-columbia-latest.osm.pbf
```



## Notes

A few decisions made in this project:

* ID column is `osm_id`
* Default to SRID 3857
* Default to same units as OpenStreetMap (e.g. km/hr and meters)
* Extra `tags` stored in `JSONB`
* Points, Lines, and Polygons are not mixed in a single table

