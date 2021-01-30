# PgOSM-Flex Performance

This page provides a rough guide of how PgOSM-Flex performance compares
against the legacy osm2pgsql load.  **This comparison is apples to oranges** but
is hopefully still helpful for planning.
The data loaded via PgOSM-Flex is much higher quality than the legacy three table load.


For a comprehensive look at how the legacy data load
time scales with different region and hardware sizes see
the blog post [Scaling osm2pgsql: Process and costs](
https://blog.rustprooflabs.com/2019/10/osm2pgsql-scaling
).

The current findings show a given region will take around longer using the
full PgOSM-Flex (`run-all.lua`) than using the legacy method.




> Note: The Flex output of osm2pgsql is currently **Experimental**
and performance characteristics are likely to shift. 




## Versions Tested

Versions used for testing.

* Ubuntu 20.04
* osm2pgsql 1.4.0
* PostgreSQL 13.1
* PostGIS 3.1


## Small sub-regions

Small sub-regions test the District of Columbia and Colorado subregions from
Geofabrik. PBF files were downloaded from Geofabrik in early January 2021.
Tested multiple machines with 64 GB RAM, multiple CPUs and fast SSDs receiving
consistent results.


* F: Flex
* PF: PgOSM-Flex

| Sub-region | Legacy (s) | F Compatible (s) | PF Road/Place (s) | PF No-Tags (s) | PF All (s) |
|    :---    |    :-:    |    :-:    |    :-:    |     :-:    |    :-:    |
|    District of Columbia    |    6    |    10    |    6     |     21    |    28    |
|    Colorado     |    62    |    90    |    72    |    217    |    270    |


> Note: THe above timings for PgOSM-Flex loads only represent the `.lua` portion.  Running the associated `.sql` script for each load is relatively fast compared to the Lua portion.


## Large regions

Initial results on larger scale tests (both data and hardware) are available
in [issue #12](https://github.com/rustprooflabs/pgosm-flex/issues/12).  As this project
matures additional performance testing results will become available.

