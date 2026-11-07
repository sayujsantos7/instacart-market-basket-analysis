-- 02b_load_pgadmin.sql : plain-SQL alternative to 02_load.sql for pgAdmin / DBeaver / any GUI
-- (GUI query windows reject psql commands such as \set and \if, which 02_load.sql uses).
--
-- Use EITHER this file OR 02_load.sql, never both (loading twice fails on the primary keys).
-- 1) Edit the six paths below. Forward slashes work on Windows, e.g. 'C:/Users/Public/Documents/Instacart Dataset/aisles.csv'.
-- 2) COPY runs on the DATABASE SERVER: the files must be readable by the server process, and your
--    role needs superuser or pg_read_server_files. If not, use pgAdmin's Import/Export tool instead.

COPY dim_aisles(aisle_id, aisle)
FROM 'C:/Users/Public/Documents/Instacart Dataset/aisles.csv' WITH (FORMAT CSV, HEADER TRUE);

COPY dim_departments(department_id, department)
FROM 'C:/Users/Public/Documents/Instacart Dataset/departments.csv' WITH (FORMAT CSV, HEADER TRUE);

COPY dim_products(product_id, product_name, aisle_id, department_id)
FROM 'C:/Users/Public/Documents/Instacart Dataset/products.csv' WITH (FORMAT CSV, HEADER TRUE);

COPY fact_orders(order_id, user_id, eval_set, order_number, order_dow, order_hour_of_day, days_since_prior_order)
FROM 'C:/Users/Public/Documents/Instacart Dataset/orders.csv' WITH (FORMAT CSV, HEADER TRUE, NULL '');

-- Line items: the prior and train files hold different orders, so they append into one table
COPY fact_order_products(order_id, product_id, add_to_cart_order, reordered)
FROM 'C:/Users/Public/Documents/Instacart Dataset/order_products__prior.csv' WITH (FORMAT CSV, HEADER TRUE);

COPY fact_order_products(order_id, product_id, add_to_cart_order, reordered)
FROM 'C:/Users/Public/Documents/Instacart Dataset/order_products__train.csv' WITH (FORMAT CSV, HEADER TRUE);

ANALYZE;
