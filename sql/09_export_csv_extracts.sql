-- 09_export_csv_extracts.sql : writes small CSV extracts of the summary tables.
-- Use them to rebuild the dashboard in Tableau or any BI tool without a live database connection.
-- Run from the repository root (paths are relative) and create the folder first:  mkdir -p exports
-- run_all.sh does both. \copy runs on the client, so no superuser rights are needed.

\copy (SELECT * FROM mv_product_basket_dynamics ORDER BY total_purchases DESC) TO 'exports/product_basket_dynamics.csv' WITH (FORMAT CSV, HEADER)
\copy (SELECT * FROM mv_customer_lifecycle ORDER BY user_id) TO 'exports/customer_lifecycle.csv' WITH (FORMAT CSV, HEADER)
\copy (SELECT * FROM mv_customer_segments ORDER BY user_id) TO 'exports/customer_segments.csv' WITH (FORMAT CSV, HEADER)
\copy (SELECT * FROM mv_slot_workload ORDER BY order_dow, order_hour_of_day) TO 'exports/slot_workload.csv' WITH (FORMAT CSV, HEADER)
\copy (SELECT * FROM mv_product_pairs ORDER BY lift DESC) TO 'exports/product_pairs.csv' WITH (FORMAT CSV, HEADER)
