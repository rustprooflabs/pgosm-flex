# PgOSM-Flex Tests


Under development - See #112.


```bash
cd tests/
```


## Test for import failures

Test for specific regions that have had failures due to unusual
tags and/or bugs in PgOSM-Flex.


Run extra region load tests.

```bash
./run-extra-loads.sh
```

## Output Tests

Load `data/district-of-columbia-2021-01-13.osm.pbf` with `run-all`
before running these tests.


Run output tests (need D.C. region loaded first).

```bash
./run-output-tests.sh
```


> PBF sourced [from Geofabrik's download service](https://download.geofabrik.de/) on January 13, 2021.



### Creating Tests

Write query. Ensure results are ordered using `COLLATE "C"` to ensure consistent ordering across
systems.


### Creating expected output


To create new tests, or to update existing tests use `psql --no-psqlrc -tA <details>`.
Example for amenity count of `osm_type`.

```bash
psql --no-psqlrc -tA  \
    -d $PGOSM_CONN \
     -f sql/amenity_osm_type_count.sql \
     > expected/amenity_osm_type_count.out
```



## Create PBFs for areas w/ Failures

Identify a feature related to the issue and load small region around
into JOSM (as if making an edit).

Use JOSM's "Save As..." to save the `<region-failure-name>.osm` file.
Use `osmium-tool` (https://osmcode.org/osmium-tool/manual.html)
to convert to `.pbf` format.

```bash
osmium cat  <region-failure-name>.osm -o <region-failure-name>.osm.pbf
mv <region-failure-name>.osm.pbf ~/git/pgosm-flex/tests/data/extra-regions/
``` 





