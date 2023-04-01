# QGIS Styles for PgOSM Flex


If you use QGIS to visualize OpenStreetMap, there are a few basic
styles using the `public.layer_styles` table created by QGIS.
This data is loaded by default. Run PgOSM Flex with `--data-only` to skip loading
this data.

QGIS can save its styling information directly in a table in the Postgres database
using a table `public.layer_styles`.



```sql
SELECT f_table_catalog, f_table_schema, f_table_name, stylename,
        useasdefault, description
    FROM public.layer_styles
;
```

