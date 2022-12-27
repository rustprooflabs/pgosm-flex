# Running osm2pgsql in append mode

## FIXME:  These docs are outdated and inaccurate

Needs updating, `--append` is removed, now under `--replication`

New option to `--update` in create/append mode making osm2pgsql's append
option available.


----


> The `--replication` feature is experimental.

----


## Using manual steps

This section documents differences from [MANUAL-STEPS-RUN.md](MANUAL-STEPS-RUN.md)


Setup - Need to use Python venv, osmium is a requirement.  Something like...

```bash
python -m venv venv && source venv/bin/activate
cd ~/git/pgosm-flex && pip install -r requirements.txt
```


Run osm2pgsql. Must use `--slim` mode without drop.


```bash
cd pgosm-flex/flex-config

osm2pgsql --output=flex --style=./run.lua \
    --slim \
    -d $PGOSM_CONN \
    ~/pgosm-data/district-of-columbia-latest.osm.pbf
```

Run the normal post-processing as you normally would.


`osm2pgsql-replication` is bundled with osm2pgsql install.

https://osm2pgsql.org/doc/manual.html#keeping-the-database-up-to-date-with-osm2pgsql-replication


Initialize replication.


```bash
osm2pgsql-replication init -d $PGOSM_CONN \
    --osm-file ~/pgosm-data/district-of-columbia-latest.osm.pbf
```



Refresh the data.  First clear out data that might violate foreign keys. Packaged
in convenient procedure.


```sql
CALL osm.append_data_start();
```

Update the data.


```bash
osm2pgsql-replication update -d $PGOSM_CONN \
    -- \
    --output=flex --style=./run.lua \
    --slim \
    -d $PGOSM_CONN
```

Refresh Mat views, rebuilds nested place polygon data.


```sql
CALL osm.append_data_finish();
```


Skip nested:

```sql
CALL osm.append_data_finish(skip_nested := True);
```

