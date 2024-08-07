# PgOSM Flex Docker

This page outlines how and when images are built and pushed to Docker Hub.


## Docker image background

The PgOSM Flex Docker image uses
[main Postgres image](https://hub.docker.com/_/postgres/)
via the [main PostGIS image](https://hub.docker.com/r/postgis/postgis)
as starting point.
Those repositories have detailed instructions on using and customizing the core
Postgres functionality.

## Images on Docker Hub

There are three main types of images pushed to Docker Hub.

* `latest`
* `x.x.x`
* `dev`

Which branch is best for you depends on how you use the data from PgOSM Flex.


### When to use tagged (`x.x.x`) release

Tagged releases are the most stable option and are recommended if you are
using `--replication` or `--update` mode.
Tagged releases are built with the latest versions of all key software, e.g. Postgres,
PostGIS and osm2pgsql, and their dependencies.  These tagged images (e.g. `0.6.2`)
are typically built at the time the tag is added to GitHub, and are (typically)
not rebuilt.

PgOSM Flex is still evolving on a regular basis. This means new tagged releases
are coming out as activity happens in the project.


### When to use `latest`

If you run PgOSM Flex without `--replication` or `--update` mode this image is
generally stable and includes the latest features.


The `latest` Docker image could include changes that
require manual changes in Postgres.  Those changes are documented in the release notes,
for example, see "Notes for `--append` users" in [0.6.1 release notes](https://github.com/rustprooflabs/pgosm-flex/releases/tag/0.6.1).


### When to use `dev`

The `dev` image exists when there's something worth testing.  Typically the `dev`
image is deleted from Docker Hub as functionality is worked into the `latest` image.



## Building the image

Build latest.  Occasionally run with `--no-cache` to force some software updates.  

```bash
docker build -t rustprooflabs/pgosm-flex .
```


Tag with version.

```bash
docker build -t rustprooflabs/pgosm-flex:0.10.0 .
```

Push to Docker Hub.

```bash
docker push rustprooflabs/pgosm-flex:latest
docker push rustprooflabs/pgosm-flex:0.10.0
```


### Ensure updates

To be certain the latest images are being used and latest
software is installed, pull the latest PostGIS image and build
the PgOSM Flex image using `--no-cache`.


```bash
docker pull postgis/postgis:16-3.4
docker build --no-cache -t rustprooflabs/pgosm-flex:dev .
```


## Building PgOSM Flex from an `osm2pgsql` feature branch

There are times it is helpful to build the PgOSM Flex Docker image with a
specific feature branch. To do this, change the `OSM2PGSQL_BRANCH` 
and/or `OSM2PGSQL_REPO` arguments as necessary at the beginning of the Dockerfile.
The production setup looks like the following example.


```Dockerfile
ARG OSM2PGSQL_BRANCH=master
ARG OSM2PGSQL_REPO=https://github.com/osm2pgsql-dev/osm2pgsql.git
```

To test the feature branch associated with
[osm2pgsql #2212](https://github.com/osm2pgsql-dev/osm2pgsql/pull/2212)
the updated version was set like the following example.
This changes the `OSM2PGSQL_BRANCH` to `check-date-on-replication-init`
and changes the username in the `OSM2PGSQL_REPO` to `lonvia`.


```Dockerfile
ARG OSM2PGSQL_BRANCH=check-date-on-replication-init
ARG OSM2PGSQL_REPO=https://github.com/lonvia/osm2pgsql.git
```

