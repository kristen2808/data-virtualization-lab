-- PostgreSQL 17. Connect directly to lab_db; execute the complete file as one statement.
-- This DO block is atomic. On error its changes are rolled back.
DO $lab$
DECLARE bad boolean;
BEGIN
  IF current_database() <> 'lab_db' THEN
    RAISE EXCEPTION 'Connect to lab_db before running this script';
  END IF;
  PERFORM pg_advisory_xact_lock(2026, 484);
CREATE TABLE IF NOT EXISTS public.customers (
  customer_id INTEGER PRIMARY KEY,
  customer_name VARCHAR(200),
  city VARCHAR(100),
  region VARCHAR(100),
  segment VARCHAR(50)
);
CREATE TABLE IF NOT EXISTS public.products (
  product_id INTEGER PRIMARY KEY,
  product_name VARCHAR(200),
  category VARCHAR(100),
  list_price DECIMAL(12,2)
);
WITH expected(table_name, column_name, data_type, nullable, position) AS (
  VALUES
    ('customers','customer_id','integer',false,1),
    ('customers','customer_name','character varying(200)',true,2),
    ('customers','city','character varying(100)',true,3),
    ('customers','region','character varying(100)',true,4),
    ('customers','segment','character varying(50)',true,5),
    ('products','product_id','integer',false,1),
    ('products','product_name','character varying(200)',true,2),
    ('products','category','character varying(100)',true,3),
    ('products','list_price','numeric(12,2)',true,4)
), actual AS (
  SELECT c.relname::text, a.attname::text,
         format_type(a.atttypid,a.atttypmod), NOT a.attnotnull, a.attnum::integer
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  JOIN pg_attribute a ON a.attrelid=c.oid
  WHERE n.nspname='public' AND c.relname IN ('customers','products')
    AND a.attnum>0 AND NOT a.attisdropped
)
SELECT EXISTS(SELECT * FROM expected EXCEPT SELECT * FROM actual)
    OR EXISTS(SELECT * FROM actual EXCEPT SELECT * FROM expected) INTO bad;
IF bad THEN
  RAISE EXCEPTION 'Incompatible public.customers/products columns, types, order or nullability';
END IF;
IF EXISTS (
  SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relname IN ('customers','products')
    AND (c.relkind <> 'r' OR c.relispartition OR c.relrowsecurity)
) OR EXISTS (
  SELECT 1 FROM pg_attribute a
  WHERE a.attrelid IN ('public.customers'::regclass,'public.products'::regclass)
    AND a.attnum>0 AND NOT a.attisdropped
    AND (a.atthasdef OR a.attidentity<>'' OR a.attgenerated<>'')
) OR EXISTS (
  SELECT 1 FROM pg_trigger WHERE tgrelid IN
    ('public.customers'::regclass,'public.products'::regclass) AND NOT tgisinternal
) OR EXISTS (
  SELECT 1 FROM pg_index WHERE indrelid IN
    ('public.customers'::regclass,'public.products'::regclass)
    AND ((indisunique AND NOT indisprimary) OR NOT indisvalid)
) OR EXISTS (
  SELECT 1 FROM pg_rewrite WHERE ev_class IN
    ('public.customers'::regclass,'public.products'::regclass) AND rulename <> '_RETURN'
) OR EXISTS (
  SELECT 1 FROM pg_constraint WHERE conrelid IN
    ('public.customers'::regclass,'public.products'::regclass) AND contype <> 'p'
) THEN
  RAISE EXCEPTION 'Unsupported table kind, RLS, defaults, generated columns, triggers or constraints';
END IF;
IF (SELECT count(*) FROM pg_constraint
    WHERE conrelid IN ('public.customers'::regclass,'public.products'::regclass)
      AND contype='p' AND conkey=ARRAY[1]::smallint[] AND NOT condeferrable) <> 2 THEN
  RAISE EXCEPTION 'Expected a non-deferrable primary key on each ID column';
END IF;
END
$lab$;
