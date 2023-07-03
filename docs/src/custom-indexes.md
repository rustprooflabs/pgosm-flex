# Indexes

PgOSM Flex allows customizing all indexes, excluding the primary key.

## INI files

Each INI file under `flex-config/indexes/` should have 4 sections defined.
These sections must be defined in order to avoid error.  Technically only the
sections with matching calls to `get_indexes_from_spec()` in
`flex-config/helpers.lua` are required.  However, it is far clearer to just
say they're all required.


The simplest index specification file is shown below.  The four (4) empty 
sections define no indexes beyond the table's `PRIMARY KEY` on the `osm_id`
column.


```ini
[all]

[point]

[line]

[polygon]
```
