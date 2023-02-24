# Developing QGIS Styles

This page explains how to maintain QGIS layer styles.

## Add/Update existing records

The QGIS table does not include `UNIQUE` constraints, so using Postgres' `UPSERT` is
not available by default.

Add new records from staging, based on object names.

```sql
INSERT INTO public.layer_styles
    (f_table_catalog, f_table_schema, f_table_name,
     f_geometry_column, stylename, styleqml, stylesld,
     useasdefault, description, "owner", ui, update_time)
SELECT new.f_table_catalog, new.f_table_schema, new.f_table_name,
     new.f_geometry_column, new.stylename, new.styleqml, new.stylesld,
     new.useasdefault, new.description, new."owner", new.ui, new.update_time
    FROM public.layer_styles_staging new
    LEFT JOIN public.layer_styles ls
        ON new.f_table_catalog = ls.f_table_catalog 
            AND new.f_table_schema = ls.f_table_schema
            AND new.f_table_name = ls.f_table_name
            AND new.stylename = ls.stylename
    WHERE ls.id IS NULL
;
```

To update existing styles.

```sql
UPDATE public.layer_styles ls
    SET f_geometry_column = new.f_geometry_column,
        styleqml = new.styleqml,
        stylesld = new.stylesld,
        useasdefault = new.useasdefault,
        description = new.description,
        "owner" = new."owner",
        ui = new.ui,
        update_time = new.update_time
    FROM public.layer_styles_staging new
    WHERE new.f_table_catalog = ls.f_table_catalog 
        AND new.f_table_schema = ls.f_table_schema
        AND new.f_table_name = ls.f_table_name
        AND new.stylename = ls.stylename
;
```


Cleanup the staging table.

```sql
DELETE FROM public.layer_styles_staging;
```


## Updating Style .sql

To update (or create new) the .sql file with styles.

Load into `_staging` table so restoring the data puts it back in the same place.
Optionally add a `WHERE` clause to only export certain styles.

You may want to update the `owner` field.

```sql
INSERT INTO public.layer_styles_staging
SELECT * FROM public.layer_styles;

UPDATE public.layer_styles_staging
    SET owner = 'rustprooflabs'
    WHERE owner != 'rustprooflabs'
;
```


```bash
pg_dump --no-owner --no-privileges --data-only --table=public.layer_styles_staging \
    -d pgosm \
    -f layer_styles.sql
```

Cleanup the staging table.

```sql
DELETE FROM public.layer_styles_staging;
```
