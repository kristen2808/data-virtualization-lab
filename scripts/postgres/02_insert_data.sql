-- PostgreSQL 17. Connect directly to lab_db; execute the complete file as one statement.
-- This DO block is atomic. On error its changes are rolled back.
DO $lab$
DECLARE bad boolean;
BEGIN
  IF current_database() <> 'lab_db' THEN
    RAISE EXCEPTION 'Connect to lab_db before running this script';
  END IF;
  PERFORM pg_advisory_xact_lock(2026, 484);
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
  LOCK TABLE public.customers, public.products IN SHARE ROW EXCLUSIVE MODE;
  CREATE TEMP TABLE expected_customers ON COMMIT DROP AS
    SELECT n::integer AS customer_id,
           ('Customer ' || lpad(n::text,4,'0'))::varchar(200) AS customer_name,
           (ARRAY['Praha','Brno','Ostrava','Plzeň','Liberec','Ústí nad Labem',
                  'Hradec Králové','Pardubice','Olomouc','Zlín','Jihlava',
                  'České Budějovice','Karlovy Vary','Kladno'])[(n-1)%14+1]::varchar(100) AS city,
           (ARRAY['Hlavní město Praha','Jihomoravský','Moravskoslezský','Plzeňský',
                  'Liberecký','Ústecký','Královéhradecký','Pardubický','Olomoucký',
                  'Zlínský','Kraj Vysočina','Jihočeský','Karlovarský','Středočeský'])[(n-1)%14+1]::varchar(100) AS region,
           (ARRAY['Retail','SMB','Enterprise','Public sector'])[(n-1)%4+1]::varchar(50) AS segment
    FROM generate_series(1,1000) AS g(n);
  CREATE TEMP TABLE expected_products ON COMMIT DROP AS
    SELECT n::integer AS product_id,
           ('Product ' || lpad(n::text,3,'0'))::varchar(200) AS product_name,
           (ARRAY['Electronics','Office','Home','Sport','Books','Tools','Garden','Clothing'])[(n-1)%8+1]::varchar(100) AS category,
           CAST(10 + n * 3.75 + (n%7) * 0.13 AS decimal(12,2)) AS list_price
    FROM generate_series(1,200) AS g(n);
  IF EXISTS (SELECT * FROM public.customers EXCEPT SELECT * FROM expected_customers)
     OR EXISTS (SELECT * FROM public.products EXCEPT SELECT * FROM expected_products) THEN
    RAISE EXCEPTION 'Existing rows differ from the deterministic fixture; nothing will be overwritten';
  END IF;
  INSERT INTO public.customers
    SELECT e.* FROM expected_customers e
    WHERE NOT EXISTS (SELECT 1 FROM public.customers t WHERE t.customer_id=e.customer_id);
  INSERT INTO public.products
    SELECT e.* FROM expected_products e
    WHERE NOT EXISTS (SELECT 1 FROM public.products t WHERE t.product_id=e.product_id);
  IF (SELECT count(*) FROM public.customers)<>1000
     OR (SELECT count(*) FROM public.products)<>200 THEN
    RAISE EXCEPTION 'Unexpected final row counts';
  END IF;
END
$lab$;
