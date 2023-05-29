# Relocate Data


 
This section describes how to relocate OpenStreetMap data loaded using PgOSM Flex.
These instructions apply to using an external Postgres database in single-import
mode.


> Do not use these instructions when using `--append`, `--update`, or `--replication`. Something will most likely break.


## Why relocate data

There are two common reasons you may want to relocate data.  The same approach
works for both of these scenarios.

* Snapshots over time
* Different regions

If your goal is to have the latest data always available, consider using
[replication](replication.md) instead.


## Rename Schema

PgOSM Flex always uses the `osm` schema.
The best way to relocate data is to simply rename the schema. This quickly moves
existing data out of the way for future PgOSM Flex use.  The following query
renames `osm` to `osm_2023_05`.


```sql
ALTER SCHEMA osm RENAME TO osm_2023_05;
```

