# PgOSM-Flex Performance

This page provides timings for how long PgOSM-Flex runs for various region sizes.
The server used for these tests has 8 vCPU and 64 GB RAM to match the target
server size [outlined in the osm2pgsql manual](https://osm2pgsql.org/doc/manual.html#preparing-the-database).

> Note: The Flex output of osm2pgsql is currently **Experimental**
and performance characteristics are likely to shift. 


## Versions Tested

Versions used for testing:

* Ubuntu 20.04
* osm2pgsql 1.4.2
* PostgreSQL 13.2
* PostGIS 3.1
* PgOSM-Flex 0.1.4


## Postgres Config



```bash
shared_buffers = 1GB
work_mem = 50MB
maintenance_work_mem = 10GB
autovacuum_work_mem = 2GB
wal_level = minimal
checkpoint_timeout = 60min
max_wal_size = 10GB
checkpoint_completion_target = 0.9
max_wal_senders = 0
random_page_cost = 1.0
```


## Road / Place

Timings to run `flex-config/run-road-place.lua` and `flex-config/run-road-place.sql` for
four (4) sub-region sizes.


```bash
osm2pgsql --slim --drop \
    --cache=30000 \
    --output=flex --style=./run-road-place.lua \
    -d $PGOSM_CONN \
    ~/pgosm-data/<subregion>-latest.osm.pbf
```

Followed by post-processing.

```bash
time psql -d $PGOSM_CONN -f run-road-place.sql
```

Last, build nested place polygons.

```bash
psql -d $PGOSM_CONN -c "CALL osm.build_nested_admin_polygons();"
```


North America is large enough that with the legacy mode ``--flat-nodes``.

IS IT??

ALSO - Try flat nodes with `cache=30000` and `cache=0`.


```bash
osm2pgsql --slim --drop \
    --cache=30000 \
    --flat-nodes=/tmp/nodes \
    --output=flex --style=./run-all.lua \
    -d $PGOSM_CONN \
    ~/pgosm-data/<subregion>-latest.osm.pbf
```



## Small sub-regions

Small sub-regions test the District of Columbia and Colorado subregions from
Geofabrik. PBF files were downloaded from Geofabrik in early January 2021.
Tested multiple machines with 64 GB RAM, multiple CPUs and fast SSDs receiving
consistent results.


| Sub-region | Legacy (s) | Flex Compatible (s) | PgOSM-Flex Road/Place (s) | PgOSM-Flex No-Tags (s) | PgOSM-Flex All (s) |
|    :---    |    :-:    |    :-:    |    :-:    |     :-:    |    :-:    |
|    District of Columbia    |    6    |    10    |    6     |     21    |    28    |
|    Colorado     |    62    |    90    |    72    |    217    |    270    |


> Note: THe above timings for PgOSM-Flex loads only represent the `.lua` portion.  Running the associated `.sql` script for each load is relatively fast compared to the Lua portion.


## Large regions

Initial results on larger scale tests (both data and hardware) are available
in [issue #12](https://github.com/rustprooflabs/pgosm-flex/issues/12).  As this project
matures additional performance testing results will become available.

## Legacy benchmarks

See the blog post
[Scaling osm2pgsql: Process and costs](https://blog.rustprooflabs.com/2019/10/osm2pgsql-scaling)
for a deeper look at how performance scales using various sizes of regions and hardware.


## Comparisons to osm2pgsql legacy output


The data loaded via PgOSM-Flex is of much higher quality than the
legacy three-table load from osm2pgsql.  Due to this fundamental switch, data loaded
via PgOSM-Flex is analysis-ready as soon as the load is done!  The legacy data model
required substantial post-processing to achieve analysis-quality data.

The limited comparsions done showed that loading a region using the
full PgOSM-Flex (`run-all.lua`) will take a few times longer than using the legacy method.

