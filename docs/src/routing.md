# Routing with PgOSM Flex

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


## Prepare for routing

Create the `pgrouting` extension if it does not already exist.
Also create the `routing` schema to store the data used in this
example.


```sql
CREATE EXTENSION IF NOT EXISTS pgrouting SCHEMA public;
CREATE SCHEMA IF NOT EXISTS routing;
```

> This command explicitly specifies the `public` schema to enforce the expected default
> and avoid unexpected behavior with custom  `search_path` settings.

### Prepare data for routing

The [pgRouting 4.0 release](https://github.com/pgRouting/pgrouting/releases/tag/v4.0.0)
removed functions previously used for data preparation in the original documentation.

The routing setup instructions are now scoped to which version of pgRouting you are
using. You can check your version with `pgr_version()`.

```sql
SELECT * FROM pgr_version();
```

```
pgr_version|
-----------+
4.0.0      |
```


Follow the instructions for your version of pgRouting.

* [Routing with pgRouting 3](./routing-3.md)
* [Routing with pgRouting 4](./routing-4.md)

> PgOSM Flex 1.1.1 and later packages `pgRouting` 4.0.
> If you are using external Postgres
> as the target for your data, the pgRouting version you have installed is in
> your control.



The 4.0 instructions have been rewritten to improve naming conventions and reduce
artifacts left behind from the process. The goal with the rewritten docs is improved
understanding and usability.

The pre-4.0 documentation used naming conventions aimed at conforming
to pgRouting's naming conventions surrounding the legacy functions.



