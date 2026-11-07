-- 04_data_quality.sql : run right after loading, BEFORE building the analytics layer.
-- Part A is a pass/fail table (every bad_rows value should be 0). A few checks encode the
-- documented structure of the Instacart dataset (e.g. one train/test order per user): if one fails
-- on the real data, investigate before assuming the load is broken.
-- Part B is informational: read it, and record anything surprising in the README.

-- ---------------------------------------------------------------------------
-- Part A: integrity checks (stored in a temp table so the last step can stop the build on a FAIL)
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS dq_results;
CREATE TEMP TABLE dq_results AS
WITH checks AS (
    SELECT 'order lines with no parent order' AS check_name, COUNT(*)::BIGINT AS bad_rows
    FROM fact_order_products fop
    LEFT JOIN fact_orders o USING (order_id)
    WHERE o.order_id IS NULL

    UNION ALL
    SELECT 'prior/train orders with no line items', COUNT(*)
    FROM fact_orders o
    LEFT JOIN fact_order_products f USING (order_id)
    WHERE f.order_id IS NULL AND o.eval_set <> 'test'

    UNION ALL
    SELECT 'test orders that unexpectedly have line items', COUNT(DISTINCT o.order_id)
    FROM fact_orders o
    JOIN fact_order_products f USING (order_id)
    WHERE o.eval_set = 'test'

    UNION ALL
    SELECT 'users without exactly one train/test order', COUNT(*)
    FROM (
        SELECT user_id
        FROM fact_orders
        GROUP BY user_id
        HAVING COUNT(*) FILTER (WHERE eval_set <> 'prior') <> 1
    ) x

    UNION ALL
    SELECT 'NULL gap on a non-first order', COUNT(*)
    FROM fact_orders
    WHERE days_since_prior_order IS NULL AND order_number <> 1

    UNION ALL
    SELECT 'non-NULL gap on a first order', COUNT(*)
    FROM fact_orders
    WHERE days_since_prior_order IS NOT NULL AND order_number = 1

    UNION ALL
    SELECT 'order_dow outside 0-6', COUNT(*)
    FROM fact_orders WHERE order_dow NOT BETWEEN 0 AND 6

    UNION ALL
    SELECT 'order_hour_of_day outside 0-23', COUNT(*)
    FROM fact_orders WHERE order_hour_of_day NOT BETWEEN 0 AND 23

    UNION ALL
    SELECT 'days_since_prior_order outside 0-30', COUNT(*)
    FROM fact_orders WHERE days_since_prior_order < 0 OR days_since_prior_order > 30

    UNION ALL
    SELECT 'reordered not 0/1', COUNT(*)
    FROM fact_order_products WHERE reordered NOT IN (0, 1)

    UNION ALL
    SELECT 'add_to_cart_order below 1', COUNT(*)
    FROM fact_order_products WHERE add_to_cart_order < 1

    UNION ALL
    SELECT 'products missing an aisle or department', COUNT(*)
    FROM dim_products WHERE aisle_id IS NULL OR department_id IS NULL
)
SELECT check_name,
       bad_rows,
       CASE WHEN bad_rows = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks;

SELECT * FROM dq_results ORDER BY (bad_rows = 0), check_name;

-- ---------------------------------------------------------------------------
-- Part B: profile (informational)
-- ---------------------------------------------------------------------------

-- Row counts
SELECT 'fact_orders' AS tbl, COUNT(*) AS row_count FROM fact_orders
UNION ALL SELECT 'fact_order_products', COUNT(*) FROM fact_order_products
UNION ALL SELECT 'dim_products',        COUNT(*) FROM dim_products
UNION ALL SELECT 'dim_aisles',          COUNT(*) FROM dim_aisles
UNION ALL SELECT 'dim_departments',     COUNT(*) FROM dim_departments;

-- Orders by eval_set (test orders exist but have no line items by design)
SELECT eval_set, COUNT(*) AS orders, COUNT(DISTINCT user_id) AS users
FROM fact_orders GROUP BY eval_set ORDER BY eval_set;

-- How much gap data sits on the 30-day ceiling (the "Day 30" spike is this, not behavior)
SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE days_since_prior_order = 30)
             / NULLIF(COUNT(days_since_prior_order), 0), 2) AS pct_gaps_at_cap
FROM fact_orders;

-- Order-count range per user. If the minimum is about 4, retention/churn cannot be measured
-- (the dataset only includes established customers).
SELECT MIN(n) AS min_orders_per_user, MAX(n) AS max_orders_per_user,
       ROUND(AVG(n), 1) AS avg_orders_per_user
FROM (SELECT user_id, COUNT(*) AS n FROM fact_orders GROUP BY user_id) u;

-- First-ever orders flagged as reorders: not expected, but not an error on its own; check the size
SELECT COUNT(*) AS first_orders_with_reordered_flag
FROM fact_orders o
JOIN fact_order_products f USING (order_id)
WHERE o.order_number = 1 AND f.reordered = 1;

-- ---------------------------------------------------------------------------
-- Gate: stop here if any integrity check failed, so no summary table is built on bad data.
-- run_all.sh stops on this error. To build anyway after you have investigated, run
-- 05_analytics_layer.sql directly (or DQ_GATE=0 ./run_all.sh).
-- ---------------------------------------------------------------------------
DO $$
DECLARE n INT;
BEGIN
    SELECT COUNT(*) INTO n FROM dq_results WHERE result = 'FAIL';
    IF n > 0 THEN
        RAISE EXCEPTION 'Data quality gate: % check(s) failed - see the PASS/FAIL table above', n;
    END IF;
END $$;
