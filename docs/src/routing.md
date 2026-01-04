# Routing with PgOSM Flex

This section provides details about routing with OpenStreetMap data loaded by
PgOSM Flex.  The primary focus of this documentation supports pgRouting 4.0
and newer, with legacy documentation available for older versions.

## Prepare for Routing

The Postgres database needs to have both [`pgrouting`](https://pgrouting.org/)
and [`convert`](https://github.com/rustprooflabs/convert) extensions installed. 
These extensions are both available in the PgOSM Flex Docker image, they are your
responsibility to install in external Postgres instances.

```sql
CREATE EXTENSION IF NOT EXISTS pgrouting;
CREATE EXTENSION IF NOT EXISTS convert;
```


## Data File for Examples

This page provides a simple example of using OpenStreetMap roads
loaded with PgOSM Flex for routing.
The example uses the D.C. PBF included under `tests/data/`.
This specific data source is chosen to provide a consistent input
for predictable results.  Even with using the same data and the
same code, some steps will have minor differences. These differences
are mentioned in those sections.

```bash
cd ~/pgosm-data

wget https://github.com/rustprooflabs/pgosm-flex/raw/main/tests/data/district-of-columbia-2021-01-13.osm.pbf
wget https://github.com/rustprooflabs/pgosm-flex/raw/main/tests/data/district-of-columbia-2021-01-13.osm.pbf.md5
```

Run `docker exec` to load the District of Columbia file from
January 13, 2021.

```bash
docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=8 \
    --region=north-america/us \
    --subregion=district-of-columbia \
    --pgosm-date=2021-01-13
```


# Prepare Data and Route

It is highly recommended to use [Routing with pgRouting 4.0](./routing-4.md).
Not all steps are backward compatible with older versions of
pgRouting. Table names, column names, and more have changed in recent versions.

The goal with the rewritten docs is improved understanding and usability.

## Legacy Routing Instructions

If you must use an older version of pgRouting, see
[Routing with pgRouting 3](./routing-3.md).
These are the legacy procedures that used pgRouting functions removed in pgRouting 4.0.

> The significnat improvements with routing in PgOSM Flex are focused on
> pgRouting 4.0 and newer. The queries used in the latest versions are not
> fully backward compatible to older version of pgRouting.


The pre-4.0 documentation used naming conventions aimed at conforming
to pgRouting's naming conventions surrounding the legacy functions.



