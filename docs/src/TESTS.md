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


## Python unit tests

The Python unit tests are under `pgosm-flex/docker/tests/`.  These tests use
Python's `unittest` module.  The `make` process runs these using
`coverage run ...` and `coverage report ...`.
See the [Makefile](https://github.com/rustprooflabs/pgosm-flex/blob/main/Makefile)
for exact implementation.


## Data import tests

Under `pgosm-flex/tests`.  The `run-output-tests.sh` script is ran by
running `make`.  The script loops over the `.sql` scripts under
`pgosm-flex/tests/sql/`, runs the queries via `psql` using
`--no-psqlrc -tA` and compares the output from the query against the
expected output saved under `pgosm-flex/tests/expected`.




> FIXME: At this time the `run-extra-loads.sh` script is not ran automatically.  There are not any usage notes covering those random side tests.


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



