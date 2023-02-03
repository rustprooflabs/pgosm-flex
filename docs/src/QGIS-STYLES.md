# QGIS Styles for PgOSM Flex


If you use QGIS to visualize OpenStreetMap, there are a few basic
styles using the `public.layer_styles` table created by QGIS.
This data is loaded by default and can be excluded with `--data-only`.


QGIS can save its styling information directly in a table in the Postgres database
using a table `public.layer_styles`.


## Prepare

The `create_layer_styles.sql` script creates the `public.layer_styles` table defined in QGIS 3.16 along with an additional `public.layer_styles_staging` table used to prepare
data before loading.

```bash
psql -d pgosm -f create_layer_styles.sql
```

Load styles to staging.

```bash
psql -d pgosm -f layer_styles.sql
```


To use these styles as defaults, update the `f_table_catalog` and
`f_table_schema` values in the staging table.  The defaults are
`f_table_catalog='pgosm'` and `f_table_schema='osm'`.


```sql
UPDATE public.layer_styles_staging
    SET f_table_catalog = 'your_db',
        f_table_schema = 'osm'
;
```

