INSERT INTO public.layer_styles
    (f_table_catalog, f_table_schema, f_table_name,
     f_geometry_column, stylename, styleqml, stylesld,
     useasdefault, description, owner, ui, update_time)
SELECT new.f_table_catalog, new.f_table_schema, new.f_table_name,
     new.f_geometry_column, new.stylename, new.styleqml, new.stylesld,
     new.useasdefault, new.description, new.owner, new.ui, new.update_time
    FROM public.layer_styles_staging new
    LEFT JOIN public.layer_styles ls
        ON new.f_table_catalog = ls.f_table_catalog 
            AND new.f_table_schema = ls.f_table_schema
            AND new.f_table_name = ls.f_table_name
            AND new.stylename = ls.stylename
    WHERE ls.id IS NULL
;