# Data updates

Keeping OpenStreetMap data recent and up-to-date is important to many projects.
However, this concept can mean very different things depending on the needs at
hand.

There are three (3) main ways to run subsequent imports using PgOSM Flex.

* [Replication](replication.md)
* [Relocate data](relocate-data.md)
* [Manual Updates](update-mode.md)

## Replication

[Replication](replication.md) should be the default first choice to consider.
Replication is best used when you only want to load one region of data and want
to keep the region's data recent.

Pros:

* Fast updates after the first import
* Easy

Cons:

* Increased database size
* Little flexibility after initial import

## Relocate data

[Relocating data](relocate-data.md) involves renaming the `osm` schema.
This allows PgOSM Flex to run in single-import mode, and to import any number
of different regions.

Pros:

* Simple
* Smaller database size per region
* Very customizable

Cons:

* Always single-import
* Duplicates a lot of data if using for snapshots over time on one region

## Manual Updates

[Manual Updates](update-mode.md) provide significant flexibility with a tradeoff
in import performance

Pros:

* Very customizable

Cons:

* Very slow updates
* Poorly documented in PgOSM Flex





