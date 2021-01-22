# Load data with PgOSM-Flex

Options to load data via osm2pgsql's Flex output are defined in Lua "styles".
PgOSM-Flex is using these styles with a mix-and-match approach.
This is best illustrated by looking within the main `run-all.lua` script.

```lua
require "all_tags"
require "run-no-tags"
```

The `run-all` style does not define any actual styles, it simply includes the `all_tags.lua` script and the `run-no-tags.lua` script.
The `tags` table contains all OSM key/value
pairs with their `osm_id` and is the largest table loaded by the main script.


## Load main tables, No Tags

As seen above, the `run_all.lua` style includes the tags table and then includes
`run-no-tags` to load the rest of the data.  If you want the main data
**without the full tags** table, use the `run-no-tags.lua` and `.sql` scripts instead.


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


## Load individual layers

One layer at a time can be added with commands such as this.  This example includes
the `road_major` style followed by the `pgosm-meta` style to track osm2pgsql
and PgOSM-Flex versions used to load the data.

```bash
osm2pgsql --slim --drop \
    --output=flex --style=./road_major.lua \
    -d pgosm \
    ~/tmp/district-of-columbia-latest.osm.pbf
```
```bash
osm2pgsql --slim --drop \
    --output=flex --style=./pgosm-meta.lua \
    -d pgosm \
    ~/tmp/district-of-columbia-latest.osm.pbf
```

Run the post-processing SQL scripts for each style.

```bash
psql -d pgosm -f ./road_major.sql
psql -d pgosm -f ./pgosm-meta.sql
```

> WARNING:  Running multiple `osm2pgsql` commands requires processing the source PBF multiple times. This can waste consdierable time on larger imports.  Further, attempting to define multiple styles with additional `--style=style.lua` switches results in only the last style being processed.  To mix and match multiple styles, create a custom Lua script similar to `run-all.lua` or `run-no-tags.lua`.


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

> The `unitable.lua` script include in in this project was[adapted from the unitable example from osm2pgsql](https://github.com/openstreetmap/osm2pgsql/blob/master/flex-config/unitable.lua). This version uses JSONB instead of HSTORE and takes advantage of `helpers.lua` to easily customize SRID.


## Customize PgOSM

Some behavior can be customized at run time with the use of environment variables.
Current environment variables:

* `PGOSM_SRID`
* `PGOSM_SCHEMA`

> WARNING:  Customizing the schema name will cause the `.sql` scripts to break.

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
Default Schema: osm
...
```

