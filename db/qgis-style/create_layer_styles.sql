
CREATE TABLE IF NOT EXISTS public.layer_styles_staging (
    id INT NOT NULL,
    f_table_catalog character varying(256),
    f_table_schema character varying(256),
    f_table_name character varying(256),
    f_geometry_column character varying(256),
    stylename character varying(30),
    styleqml xml,
    stylesld xml,
    useasdefault boolean,
    description text,
    owner character varying(30),
    ui xml,
    update_time timestamp without time zone DEFAULT now(),
    type character varying
);

COMMENT ON TABLE public.layer_styles_staging IS 'Staging table to load QGIS Layer Styles.  Similar to QGIS-created table, no primary key.';

-- Type column required for QGIS 3.16, possibly earlier versions.
CREATE TABLE IF NOT EXISTS public.layer_styles (
    id SERIAL NOT NULL,
    f_table_catalog character varying(256),
    f_table_schema character varying(256),
    f_table_name character varying(256),
    f_geometry_column character varying(256),
    stylename character varying(30),
    styleqml xml,
    stylesld xml,
    useasdefault boolean,
    description text,
    owner character varying(30),
    ui xml,
    update_time timestamp without time zone DEFAULT now(),
    type character varying,
    CONSTRAINT layer_styles_pkey PRIMARY KEY (id)
);
