# PgOSM Docker

Notes covering Docker and generating image for Docker Hub.

Uses [main Postgres image](https://hub.docker.com/_/postgres/) via the [main PostGIS image](https://hub.docker.com/r/postgis/postgis) as starting point, see that
repo for full instructions on using the core Postgres functionality.

Build latest.

```
docker build -t rustprooflabs/pgosm-flex .
```


Tag with Pg version.

```
docker build -t rustprooflabs/pgosm-flex:pg13 .
```

> Note: Update the Dockerfile to build with non-default Postgres/PostGIS version.

Push to Dockerhub

```
docker push rustprooflabs/pgosm-flex:pg12
docker push rustprooflabs/pgosm-flex:pg13
docker push rustprooflabs/pgosm-flex:latest
```
