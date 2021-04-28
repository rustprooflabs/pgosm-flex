# PgOSM-Flex Tests

Under development - See #112.

## Data

Load `data/district-of-columbia-2021-01-13.osm.pbf` for all tests.

PBF sourced [from Geofabrik's download service](https://download.geofabrik.de/)
on January 13, 2021.


Run tests

```bash
./run-tests.sh
```



## Creating expected output


To create new tests, or to update existing tests use `psql --no-psqlrc -tA <details>`.
Example for amenity count of `osm_type`.

```bash
psql --no-psqlrc -tA  \
    -d $PGOSM_CONN \
     -f sql/amenity_osm_type_count.sql \
     > expected/amenity_osm_type_count.out
```

