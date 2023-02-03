# PgOSM Flex

PgOSM Flex ([GitHub](https://github.com/rustprooflabs/pgosm-flex))
provides high quality OpenStreetMap datasets in PostGIS using the
[osm2pgsql Flex output](https://osm2pgsql.org/doc/manual.html#the-flex-output).
This project provides a curated set of Lua and SQL scripts to clean and organize
the most commonly used OpenStreetMap data, such as roads, buildings, and points of interest (POIs).

Running PgOSM Flex is easy via the PgOSM Docker image
[hosted on Docker Hub](https://hub.docker.com/repository/docker/rustprooflabs/pgosm-flex).


1. The [quick start](QUICK-START.md) shows how easy it is to get started
1. Change how PgOSM Flex runs with [common customizations](COMMON-CUSTOMIZATION.md)
1. [Customize layersets](LAYERSETS.md) to change what data you load


## Project goals

* High quality spatial data
* Reliable
* Easy to customize
* Easy to use


## Project decisions

A few decisions made in this project:

* ID column is `osm_id`
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
* osm2pgsql 1.8.0

Defining [Postgres indexes in the Lua styles](https://osm2pgsql.org/doc/manual.html#defining-indexes)
bumps osm2pgsql minimum requirement to 1.8.0.

This project will attempt, but not guarantee, to support PostgreSQL 12 until it
reaches it EOL support.


## Minimum Hardware

### RAM

osm2pgsql requires [at least 2 GB RAM](https://osm2pgsql.org/doc/manual.html#main-memory).

### Storage

Fast SSD drives are strongly recommended.  It should work on slower storage devices (HDD,
SD, etc),
however the [osm2pgsql-tuner](https://github.com/rustprooflabs/osm2pgsql-tuner)
package used to determine the best osm2pgsql command assumes fast SSDs.

