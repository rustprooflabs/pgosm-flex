# PgOSM-Flex Performance

This page provides timings for how long PgOSM-Flex runs for various region sizes.
The server used to host these tests has 8 vCPU and 64 GB RAM to match the target
server size [outlined in the osm2pgsql manual](https://osm2pgsql.org/doc/manual.html#preparing-the-database).


## Versions Tested

Versions used for testing: PgOSM Flex 0.4.7 Docker image, based on the offical
PostGIS image with Postgres 14 / PostGIS 3.2.


## Layerset:  Minimal

The `minimal` layer set only loads major roads, places, and POIs.

Timings with nested admin polygons and dumping the processed data to a `.sql`
file.


| Sub-region            | PBF Size | PostGIS Size | `.sql` Size |  Import Time  |
| :---                  |    :-:    |      :-:    |    :-:      |      :-:      |
| District of Columbia  |   18 MB   |    36 MB    |    14 MB    |    15.3 sec   |
| Colorado              |   226 MB  |    181 MB   |   129 MB    | 1 min 23 sec  |
| Norway                |   1.1 GB  |    618 MB   |   489 MB    | 5 min 36 sec  |
| North America         |   12 GB   |    9.5 GB   |   7.7 GB    |  3.03 hours   |



Timings skipping nested admin polygons the dump to `.sql`.  This adds
`--skip-dump --skip-nested` to the `docker exec process`.


| Sub-region            |  Import Time  |
| :---                  |      :-:      |
| District of Columbia  |    15.0 sec   |
| Colorado              | 1 min 21 sec  |
| Norway                | 5 min 12 sec  |
| North America         |  1.25 hours   |


## Layerset:  Default

The `default` layer set....

Timings with nested admin polygons and dumping the processed data to a `.sql`
file.


| Sub-region            | PBF Size  | PostGIS Size | `.sql` Size |  Import Time  |
| :---                  |    :-:    |      :-:     |    :-:      |      :-:      |
| District of Columbia  |   18 MB   |    ZZ MB     |    ZZ MB    |    ZZZZ sec   |
| Colorado              |   226 MB  |    ZZZ MB    |   1.9 GB    | 8 min 20 sec  |
| Norway                |   1.1 GB  |    ZZZ MB    |   ZZZ GB    | Z min ZZ sec  |
| North America         |   ZZ GB   |     ZZ GB    |    ZZ GB    |      ZZZ      |



Timings skipping nested admin polygons the dump to `.sql`.  This adds
`--skip-dump --skip-nested` to the `docker exec process`.


| Sub-region            |  Import Time  |
| :---                  |      :-:      |
| District of Columbia  |    ZZZZ sec   |
| Colorado              | Z min Z sec   |
| Norway                | Z min Z sec   |
| North America         |      ZZZ      |


## Methodology

The timing for the first `docker exec` for each region was discarded as
it included the timing for downloading the PBF file.

Timings are an average of multiple recorded test runs over more than one day.
For example, the Norway region for the `minimal` layerset had two times: 5 min 35 seconds
and 5 minutes 37 seconds for an average of 5 minutes 36 seconds.

Time for the import step is reported using the Linux `time` command on the `docker exec`
step as shown in the following commands.


`PostGIS Size` reported is according to the meta-data in Postgres exposed through
the [PgDD extension](https://github.com/rustprooflabs/pgdd) using this query.

```sql
SELECT db_size
    FROM dd.database
;
```


### Commands

```bash
export POSTGRES_USER=postgres
export POSTGRES_PASSWORD=mysecretpassword

docker run --name pgosm -d --rm \
    -v ~/pgosm-data:/app/output \
    -v /etc/localtime:/etc/localtime:ro \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    -p 5433:5432 -d rustprooflabs/pgosm-flex \
    -c shared_buffers=1GB \
    -c work_mem=50MB \
    -c maintenance_work_mem=10GB \
    -c autovacuum_work_mem=2GB \
    -c checkpoint_timeout=300min \
    -c max_wal_senders=0 -c wal_level=minimal \
    -c max_wal_size=10GB \
    -c checkpoint_completion_target=0.9 \
    -c random_page_cost=1.0 \
    -c full_page_writes=off \
    -c fsync=off


time docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=64 \
    --region=north-america/us \
    --subregion=colorado \
    --layerset=minimal
```

> WARNING:  Setting `full_page_writes=off` and `fsync=off` is part of the [expert tuning](https://osm2pgsql.org/doc/manual.html#expert-tuning) for the best possible performance.  This is deemed acceptable in this Docker container running `--rm`, obviously this container will be discarded immediately after processing. **DO NOT** use these configurations unless you understand and accept the risks of corruption.




## Other testing

Initial results on larger scale tests (both data and hardware) are available
in [issue #12](https://github.com/rustprooflabs/pgosm-flex/issues/12).  As this project
matures additional performance testing results will become available.

### Legacy benchmarks

See the blog post
[Scaling osm2pgsql: Process and costs](https://blog.rustprooflabs.com/2019/10/osm2pgsql-scaling)
for a deeper look at how performance scales using various sizes of regions and hardware.

### Comparisons to osm2pgsql legacy output

The data loaded via PgOSM-Flex is of much higher quality than the
legacy three-table load from osm2pgsql.  Due to this fundamental switch, data loaded
via PgOSM-Flex is analysis-ready as soon as the load is done!  The legacy data model
required substantial post-processing to achieve analysis-quality data.

The limited comparsions show that loading a region using the
default PgOSM Flex layerset will take a few times longer than using the legacy method.

