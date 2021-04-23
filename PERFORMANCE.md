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


## Road / Place

The `run-road-place` layer set is a minimal set only loads roads and places,
7 tables and 3 views.



| Sub-region            | PBF Size | PostGIS Size | Import (s) | Post-import (s) | Nested Places (s) |
| :---                  |    :-:    |      :-:    |    :-:    |       :-:        |   :-:   |
| District of Columbia  |   17 MB   |    60 MB    |    10     |       0.3        |   0.08  |
| Colorado              |   208 MB  |    398 MB   |    111    |       4.3        |   2.5   |
| Norway                |   909 MB  |    797 MB   |    402    |       34         |   20    |
| North America         |   11 GB   |     17 GB   |    4884   |       281        |   4174  |



## No Tags

The `run-no-tags` layer set loads nearly all of the data, excluding the unstructured
`tags` data.  35 tables and 6 views.



| Sub-region            | PBF Size  | PostGIS Size | Import (s) | Post-import (s) |
| :---                  |    :-:    |     :-:      |    :-:     |       :-:       |
| District of Columbia  |   17 MB   |    182 MB    |    42      |      2.3        |
| Colorado              |   208 MB  |    1449 MB   |    391     |       19        |
| Norway                |   909 MB  |    3.8 GB    |    1403    |       57        |
| North America         |   11 GB   |    65 GB     |    18809   |       1076      |




## Methodology

Timings are an average of multiple recorded test runs over more than one day.
For example, the North America `run-road-place.lua` had two times: 4,845 seconds and 4,922 seconds for an average of 4,884 s
(1 hour 21 minutes).
The difference of these two runs was only 1 minute 17 seconds, a rather small
amount of variation.

Time for the import step is reported directly from osm2gpsql while the psql commands use the Linux `time` command as shown in the commands above.


`PostGIS Size` reported is according to the meta-data in Postgres exposed through
the [PgDD extension](https://github.com/rustprooflabs/pgdd) using this query.

```sql
SELECT size_plus_indexes
	FROM dd.schemas
	WHERE s_name = 'osm'
;
```



### Commands

D.C., Colorado, and Norway imports used this command format.


```bash
osm2pgsql --slim --drop \
    --cache=30000 \
    --output=flex --style=./run-<layer-set-name>.lua \
    -d $PGOSM_CONN \
    ~/pgosm-data/<subregion>-latest.osm.pbf
```

North America loaded using `--flat-nodes` and sets `--cache=0`.

```bash
osm2pgsql --slim --drop \
    --cache=0 \
    --flat-nodes=/tmp/nodes \
    --output=flex --style=./run-<layer-set-name>lua \
    -d $PGOSM_CONN \
    ~/pgosm-data/<subregion>-latest.osm.pbf
```

All regions use the same post-processing command and build nested polygons.

```bash
time psql -d $PGOSM_CONN -f run-<layer-set-name>.sql
time psql -d $PGOSM_CONN -c "CALL osm.build_nested_admin_polygons();"
```

## Postgres Config

Postgres is configured per the [suggestions in the osm2pgsql manual](https://osm2pgsql.org/doc/manual.html#preparing-the-database).


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


## Other testing

Initial results on larger scale tests (both data and hardware) are available
in [issue #12](https://github.com/rustprooflabs/pgosm-flex/issues/12).  As this project
matures additional performance testing results will become available.

### Legacy benchmarks

See the blog post
[Scaling osm2pgsql: Process and costs](https://blog.rustprooflabs.com/2019/10/osm2pgsql-scaling)
for a deeper look at how performance scales using various sizes of regions and hardware.

### Comparisons to osm2pgsql legacy output

The data loaded via PgOSM-Flex is of much higher quality than the
legacy three-table load from osm2pgsql.  Due to this fundamental switch, data loaded
via PgOSM-Flex is analysis-ready as soon as the load is done!  The legacy data model
required substantial post-processing to achieve analysis-quality data.

The limited comparsions done showed that loading a region using the
full PgOSM-Flex (`run-all.lua`) will take a few times longer than using the legacy method.

