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

If you're using `--append` mode, tagged releases are the most stable option.
Tagged releases are built with the latest versions of all key software, e.g. Postgres,
PostGIS and osm2pgsql, and their dependencies.  These tagged images (e.g. `0.6.2`)
are typically built at the time the tag is added to GitHub, and are (typically)
not rebuilt.

PgOSM Flex is still evolving on a regular basis. This means new tagged releases
are coming out as activity happens in the project.


### When to use `latest`

If you run PgOSM Flex without `--append` mode this image is generally stable and
includes the latest features.


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
docker build -t rustprooflabs/pgosm-flex:0.6.2 .
```

Push to Docker Hub.

```bash
docker push rustprooflabs/pgosm-flex:latest
docker push rustprooflabs/pgosm-flex:0.6.2
```
