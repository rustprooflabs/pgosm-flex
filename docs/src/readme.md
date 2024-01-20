# PgOSM Flex

PgOSM Flex ([GitHub](https://github.com/rustprooflabs/pgosm-flex))
provides high quality OpenStreetMap datasets in PostGIS using the
[osm2pgsql Flex output](https://osm2pgsql.org/doc/manual.html#the-flex-output).
This project provides a curated set of Lua and SQL scripts to clean and organize
the most commonly used OpenStreetMap data, such as roads, buildings, and points of interest (POIs).

Running PgOSM Flex is easy via the PgOSM Docker image
[hosted on Docker Hub](https://hub.docker.com/repository/docker/rustprooflabs/pgosm-flex).


1. The [quick start](quick-start.md) shows how easy it is to get started
1. Change how PgOSM Flex runs with [common customizations](common-customization.md)
1. [Customize layersets](layersets.md) to change what data you load
1. Configure [connection to external](postgres-external.md) database, and use [replication](replication.md)


## Project goals

* High quality spatial data
* Reliable
* Easy to customize
* Easy to use


## Project decisions

A few decisions made in this project:

* ID column is `osm_id` and is always `PRIMARY KEY`
* Geometry column named `geom`
* Defaults to same units as OpenStreetMap (e.g. km/hr, meters)
* Data not included in a dedicated column is available from `osm.tags.tags` (`JSONB`)
* Points, Lines, and Polygons are not mixed in a single table
* Tracks latest Postgres, PostGIS, and osm2pgsql versions

This project's approach is to do as much processing in the Lua styles
passed along to osm2pgsql, with post-processing steps creating indexes,
constraints and comments.


## Versions Supported

Minimum versions supported:

* Postgres 12
* PostGIS 3.0

This project will attempt, but not guarantee, to support PostgreSQL 12 until it
reaches it EOL support.

The Docker image is pinned to osm2pgsql's `master` branch. Users of the Docker image
naturally use the latest version of osm2pgsql at the time the Docker image was created.

This project has not been officially tested on Windows.

## Minimum Hardware

### RAM

osm2pgsql requires [at least 2 GB RAM](https://osm2pgsql.org/doc/manual.html#main-memory).

### Storage

Fast SSD drives are strongly recommended.  It should work on slower storage devices (HDD,
SD, etc),
however the [osm2pgsql-tuner](https://github.com/rustprooflabs/osm2pgsql-tuner)
package used to determine the best osm2pgsql command assumes fast SSDs.

## RustProof Labs project

PgOSM Flex is a RustProof Labs project developed and maintained by Ryan Lambert.
See the [RustProof Labs blog](https://blog.rustprooflabs.com/category/pgosm-flex)
for more resources and examples of using PgOSM Flex.
