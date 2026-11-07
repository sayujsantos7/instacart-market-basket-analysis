-- 03_indexes.sql : built after the load (faster than indexing during COPY). Safe to re-run.

-- Customer order-history scans and latency tracking
CREATE INDEX IF NOT EXISTS idx_orders_user_number ON fact_orders (user_id, order_number);

-- Product lookups for basket / co-occurrence queries
-- (order_id lookups are already served by the (order_id, product_id) primary key)
CREATE INDEX IF NOT EXISTS idx_order_products_product ON fact_order_products (product_id);

-- Removed: an index on add_to_cart_order. It has very low selectivity, nothing here filters on it
-- in a way it would help, and it costs disk space and load time. Drops it for anyone who built it earlier.
DROP INDEX IF EXISTS idx_order_products_cart_pos;

ANALYZE;
