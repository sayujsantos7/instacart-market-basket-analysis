-- 02_load.sql : bulk-load the raw Kaggle CSVs, then refresh planner statistics.
--
-- Usage:   psql -d instacart_db -v data_dir='/path/to/csv/folder' -f sql/02_load.sql
-- If data_dir is not supplied, the default below is used.
--
-- NOTE: COPY runs on the *database server* and needs superuser or the pg_read_server_files role.
-- If the server cannot see your files, replace each COPY with psql's client-side \copy
-- (\copy does not accept variables, so you would type the path in directly).

\if :{?data_dir}
\else
    \set data_dir 'C:/Users/Public/Documents/Instacart Dataset'
\endif

\set aisles_file      :data_dir '/aisles.csv'
\set departments_file :data_dir '/departments.csv'
\set products_file    :data_dir '/products.csv'
\set orders_file      :data_dir '/orders.csv'
\set prior_file       :data_dir '/order_products__prior.csv'
\set train_file       :data_dir '/order_products__train.csv'

COPY dim_aisles(aisle_id, aisle)
FROM :'aisles_file' WITH (FORMAT CSV, HEADER TRUE);

COPY dim_departments(department_id, department)
FROM :'departments_file' WITH (FORMAT CSV, HEADER TRUE);

COPY dim_products(product_id, product_name, aisle_id, department_id)
FROM :'products_file' WITH (FORMAT CSV, HEADER TRUE);

COPY fact_orders(order_id, user_id, eval_set, order_number, order_dow, order_hour_of_day, days_since_prior_order)
FROM :'orders_file' WITH (FORMAT CSV, HEADER TRUE, NULL '');

-- Line items: the prior and train files hold different orders, so they append into one table
COPY fact_order_products(order_id, product_id, add_to_cart_order, reordered)
FROM :'prior_file' WITH (FORMAT CSV, HEADER TRUE);

COPY fact_order_products(order_id, product_id, add_to_cart_order, reordered)
FROM :'train_file' WITH (FORMAT CSV, HEADER TRUE);

-- Give the query planner statistics on the freshly loaded data
ANALYZE;
