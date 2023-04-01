# Processing Time

The purpose of this page is to provide a rough guideline of what to
expect for how long PgOSM Flex processing will take.
Two server sizes are used for this testing hosted by Digital Ocean.
The larger size server
has 8 vCPU and 64 GB RAM to match the target
server size [outlined in the osm2pgsql manual](https://osm2pgsql.org/doc/manual.html#preparing-the-database). The current matching Digital Ocean
resource class is the Memory-Optimized with dedicated CPU resources.
This comes with a 200 GB SSD. The cost for this class of instance
is $0.500 / hour, or $336 / month.  A good number of production Postgres
instances can run on this hardware.

The smaller server size is a budget friendly 2 AMD vCPU and 2 GB RAM
on shared CPU resources. The cost for this class of instance is
$0.031 / hour, or $21 / month.




## Versions Tested

Versions used for testing: PgOSM Flex 0.7.1 Docker image, based on the official
PostGIS image with Postgres 15.2 / PostGIS 3.3.  osm2pgsql 1.8.1.



Note: Postgres 15 [made GIST indexes faster](https://osm2pgsql.org/news/2023/01/22/faster-with-postgresql15.html)
to create.  Using an version prior to Postgres 14 will likely take longer.


## Methodology

Create instance, Ubuntu 22.04.

```bash
sudo apt update \
    && sudo apt upgrade -y \
    && sudo apt autoremove -y \
    && sudo apt install -y apt-transport-https ca-certificates curl software-properties-common \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && sudo apt update \
    && sudo apt install docker-ce \
    && sudo reboot -h now
```




The timing for the first `docker exec` for each region was discarded as
it included the timing for downloading the PBF file.

Timings are an average of multiple recorded test runs over more than one day.
For example, the Norway region for the `minimal` layerset had two times: 5 min 35 seconds
and 5 minutes 37 seconds for an average of 5 minutes 36 seconds.

Time for the import step is reported using the Linux `time` command on the `docker exec`
step as shown in the following commands.


`PostGIS Size` reported is according to the meta-data in Postgres using this query.

```sql
SELECT d.oid, d.datname AS db_name,
        pg_size_pretty(pg_database_size(d.datname)) AS db_size
    FROM pg_catalog.pg_database d
    WHERE d.datname = current_database()
```


### Commands

Set environment variables and start `pgosm` Docker container with configurations
set per the [osm2pgsql tuning guidelines](https://osm2pgsql.org/doc/manual.html#tuning-the-postgresql-server).


```bash
export POSTGRES_USER=postgres
export POSTGRES_PASSWORD=mysecretpassword

docker run --name pgosm -d --rm \
    -v ~/pgosm-data:/app/output \
    -v /etc/localtime:/etc/localtime:ro \
    -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
    -p 5433:5432 -d rustprooflabs/pgosm-flex:0.7.1 \
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
```

> WARNING:  Setting `full_page_writes=off` and `fsync=off` is part of the [expert tuning](https://osm2pgsql.org/doc/manual.html#expert-tuning) for the best possible performance.  This is deemed acceptable in this Docker container running `--rm`, obviously this container will be discarded immediately after processing. **DO NOT** use these configurations unless you understand and accept the risks of corruption.



Run PgOSM Flex within Docker.  The first run time is discarded because the first
run time includes time downloading the PBF file.  Subsequent runs only include the 
time running the processing.

```bash

time docker exec -it \
    pgosm python3 docker/pgosm_flex.py \
    --ram=64 \
    --region=north-america/us \
    --subregion=colorado \
    --layerset=minimal
```





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
`--skip-dump --skip-nested` to the `docker exec process`. The following
table compares the import time using these skips against the full times reported
above.


| Sub-region            |  Import Time (full)  |  Import Time (skips)  |
| :---                  |         :-:          |         :-:           |
| District of Columbia  |        15.3 sec      |        15.0 sec       |
| Colorado              |     1 min 23 sec     |     1 min 21 sec      |
| Norway                |     5 min 36 sec     |     5 min 12 sec      |
| North America         |      3.03 hours      |      1.25 hours       |


## Layerset:  Default

The `default` layer set....

Timings with nested admin polygons and dumping the processed data to a `.sql`
file.


| Sub-region            | PBF Size  | PostGIS Size | `.sql` Size |  Import Time  |
| :---                  |    :-:    |      :-:     |    :-:      |      :-:      |
| District of Columbia  |   18 MB   |    212 MB    |   160 MB    |     53 sec    |
| Colorado              |   226 MB  |    2.1 GB    |   1.9 GB    | 8 min 20 sec  |
| Norway                |   1.1 GB  |    7.2 GB    |   6.5 GB    | 33 min 44 sec |
| North America         |   12 GB   |     98 GB    |    55 GB    |   8.78 hours  |



Timings skipping nested admin polygons the dump to `.sql`.  This adds
`--skip-dump --skip-nested` to the `docker exec process`. The following
table compares the import time using these skips against the full times reported
above.


| Sub-region            |  Import Time (full) |  Import Time (skips)  |
| :---                  |         :-:         |          :-:          |
| District of Columbia  |        53 sec       |         51 sec        |
| Colorado              |    8 min 20 sec     |     7 min 55 sec      |
| Norway                |    33 min 44 sec    |    32 min 18 sec      |
| North America         |      8.78 hours     |      6.58 hours       |


