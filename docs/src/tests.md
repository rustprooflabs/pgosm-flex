# Testing PgOSM Flex

The `Makefile` at the root of this project tests many core aspects of
PgOSM Flex's functionality.  It builds the Docker image, tests a few usage
scenarios (including `--input-file`) and runs both Python unit tests
and Data Import tests.  The data import tests verify row counts by
`osm_type` and `osm_subtype` of many tables.


## Run all tests

To run all tests run `make` from the project's root directory.

```bash
make
```

A simplified usage for quicker testing during development.

```bash
make docker-exec-default unit-tests
```

## Data Tests

Under `pgosm-flex/tests`.  The `run-output-tests.sh` script is ran by
running `make`.  The script loops over the `.sql` scripts under
`pgosm-flex/tests/sql/`, runs the queries via `psql` using
`--no-psqlrc -tA` and compares the output from the query against the
expected output saved under `pgosm-flex/tests/expected`.
Running `make docker-exec-default unit-tests` should finish with this line
reporting data tests completed successfully.


```bash
Data output tests completed successfully.
```

If something in the Lua styles or SQL post-processing changes, the intention is
they will be reported by these tests.   Note the second line of this section
reports the `docker exec` command to run in order to see the changes to the
data tests.

```bash
FAILED TEST: sql/shop_polygon_osm_type_subtype_count.sql - See tmp/shop_polygon_osm_type_subtype_count.diff
  docker exec -it pgosm /bin/bash -c "cat /app/tests/tmp/shop_polygon_osm_type_subtype_count.diff " 
One or more data output tests failed.
```

The output from the `docker exec` command looks like the following.
Note the `-` and `+` lines showing the count of records with
`osm_type='shop'` and `osm_subtype='chemist'` changed from 1 to 2.


```bash
diff --git a/expected/shop_polygon_osm_type_subtype_count.out b/tmp/shop_polygon_osm_type_subtype_count.out
index 75c16c3..2385d8d 100644
--- a/expected/shop_polygon_osm_type_subtype_count.out
+++ b/tmp/shop_polygon_osm_type_subtype_count.out
@@ -12,7 +12,7 @@ shop|books|1
 shop|car|4
 shop|car_parts|3
 shop|car_repair|7
-shop|chemist|1
+shop|chemist|2
 shop|clothes|8
 shop|convenience|35
 shop|copyshop|1
```


### Add / Update Data Tests

This section provides guidance to adding/updating data tests for PgOSM Flex.
The SQL file to run is under `tests/sql/*.sql`, the expected results are saved
under `tests/expected/*.out`.


#### Load Test Data

Load `data/district-of-columbia-2021-01-13.osm.pbf` with `run-all`
before running these tests.


> PBF sourced [from Geofabrik's download service](https://download.geofabrik.de/) on January 13, 2021.

#### Craft Test Query

Connect to the PgOSM Flex database with `data/district-of-columbia-2021-01-13.osm.pbf`
loaded.  Write the query that provide results to test for.

Important:  Results must be ordered using `COLLATE "C"` to ensure consistent
ordering across systems.  For example it should be written like this:

```sql
SELECT osm_type COLLATE "C", COUNT(*)
    FROM osm.amenity_point
    GROUP BY osm_type COLLATE "C"
    ORDER BY osm_type COLLATE "C"
;
```

Not like this:

```sql
SELECT osm_type, COUNT(*)
    FROM osm.amenity_point
    GROUP BY osm_type
    ORDER BY osm_type
;
```



#### Create Expected Output


To create new tests, or to update existing tests use `psql --no-psqlrc -tA <details>`.
Example for amenity count of `osm_type`.

Assuming [Quick Start](quick-start.md) instructions, set the env var for the Postgres
connection first.

```bash
export PGOSM_CONN=postgresql://postgres:mysecretpassword@localhost:5433/pgosm
```

Run the query, save the output. 

```bash
psql --no-psqlrc -tA  \
    -d $PGOSM_CONN \
     -f sql/amenity_osm_type_count.sql \
     > expected/amenity_osm_type_count.out
```

#### Validate New Tests

Ensure the data tests work and are reported if values change via `make`.
The best way to ensure the test is working is manually change one value in the
generated `.out` file which should cause the following error message.
Setting the `.out` data back to right should return the message back to successful.

```bash
FAILED TEST: sql/shop_polygon_osm_type_subtype_count.sql - See tmp/shop_polygon_osm_type_subtype_count.diff
  docker exec -it pgosm /bin/bash -c "cat /app/tests/tmp/shop_polygon_osm_type_subtype_count.diff " 
One or more data output tests failed.
```



----

### Create PBFs for areas w/ Failures

Identify a feature related to the issue and load small region around
into JOSM (as if making an edit).

Use JOSM's "Save As..." to save the `<region-failure-name>.osm` file.
Use `osmium-tool` (https://osmcode.org/osmium-tool/manual.html)
to convert to `.pbf` format.

```bash
osmium cat  <region-failure-name>.osm -o <region-failure-name>.osm.pbf
mv <region-failure-name>.osm.pbf ~/git/pgosm-flex/tests/data/extra-regions/
``` 


### Test for import failures

Test for specific regions that have had failures due to unusual
tags and/or bugs in PgOSM-Flex.


Run extra region load tests.



```bash
export PGOSM_CONN=pgosm_tests
export PGOSM_CONN_PG=postgres
./run-extra-loads.sh
```

> FIXME: At this time the `run-extra-loads.sh` script is not ran automatically.  There are not any usage notes covering those random side tests.



## Python unit tests

The Python unit tests are under `pgosm-flex/docker/tests/`.  These tests use
Python's `unittest` module.  The `make` process runs these using
`coverage run ...` and `coverage report ...`.
See the [Makefile](https://github.com/rustprooflabs/pgosm-flex/blob/main/Makefile)
for exact implementation.

These unit tests cover specific logic and functionality to how PgOSM Flex's Python
program runs.

----


## What is not tested

Functionality of `osm2pgsql-replication` to actually update data.  Challenge
is that to test this it requires having a recent `.osm.pbf` file for the initial
import. Attempting to use the test D.C. file used for all other testing
(from January 13, 2021), the initial import works, however a subsequent
refresh fails.

```bash
2023-01-29 08:11:35,553:INFO:pgosm-flex:helpers:2023-01-29 08:11:35 [INFO]: Using replication service 'http://download.geofabrik.de/north-america/us/district-of-columbia-updates'. Current sequence 2856 (2021-01-13 14:42:03-07:00).
2023-01-29 08:11:36,866:INFO:pgosm-flex:helpers:Traceback (most recent call last):
2023-01-29 08:11:36,866:INFO:pgosm-flex:helpers:File "/usr/local/bin/osm2pgsql-replication", line 556, in <module>
2023-01-29 08:11:36,866:INFO:pgosm-flex:helpers:sys.exit(main())
2023-01-29 08:11:36,866:INFO:pgosm-flex:helpers:File "/usr/local/bin/osm2pgsql-replication", line 550, in main
2023-01-29 08:11:36,867:INFO:pgosm-flex:helpers:return args.handler(conn, args)
2023-01-29 08:11:36,867:INFO:pgosm-flex:helpers:File "/usr/local/bin/osm2pgsql-replication", line 402, in update
2023-01-29 08:11:36,867:INFO:pgosm-flex:helpers:endseq = repl.apply_diffs(outhandler, seq + 1,
2023-01-29 08:11:36,867:INFO:pgosm-flex:helpers:File "/usr/local/lib/python3.9/dist-packages/osmium/replication/server.py", line 177, in apply_diffs
2023-01-29 08:11:36,868:INFO:pgosm-flex:helpers:diffs = self.collect_diffs(start_id, max_size)
2023-01-29 08:11:36,868:INFO:pgosm-flex:helpers:File "/usr/local/lib/python3.9/dist-packages/osmium/replication/server.py", line 143, in collect_diffs
2023-01-29 08:11:36,868:INFO:pgosm-flex:helpers:left_size -= rd.add_buffer(diffdata, self.diff_type)
2023-01-29 08:11:36,868:INFO:pgosm-flex:helpers:RuntimeError: gzip error: inflate failed: incorrect header check
2023-01-29 08:11:36,890:WARNING:pgosm-flex:pgosm_flex:Failure. Return code: 1
2023-01-29 08:11:36,890:INFO:pgosm-flex:pgosm_flex:Skipping pg_dump
2023-01-29 08:11:36,890:WARNING:pgosm-flex:pgosm_flex:PgOSM Flex completed with errors. Details in output
```
