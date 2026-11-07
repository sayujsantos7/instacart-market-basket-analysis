-- 05_analytics_layer.sql : builds the summary tables the dashboard and insight queries read.
-- Safe to re-run (every object is dropped and rebuilt). Run AFTER 04_data_quality.sql passes.
--
-- Naming note: the mv_* objects are plain tables rebuilt by this script, not PostgreSQL
-- MATERIALIZED VIEWs. The names are kept because the Tableau workbook connects to them.

-- Session tuning for the large aggregations below (session-level only).
-- On a machine with under ~8 GB RAM, lower work_mem (e.g. '128MB') and maintenance_work_mem ('512MB').
SET work_mem = '512MB';
SET maintenance_work_mem = '1GB';
SET max_parallel_workers_per_gather = 4;

-- ---------------------------------------------------------------------------
-- 1. Product basket dynamics: cart position + reorder behaviour (products with >= 100 purchases)
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS mv_product_pairs;          -- depends on this table's logic; rebuilt below
DROP TABLE IF EXISTS mv_product_basket_dynamics;

CREATE TABLE mv_product_basket_dynamics AS
SELECT
    p.product_id,
    p.product_name,
    d.department,
    a.aisle,
    COUNT(*) AS total_purchases,
    ROUND(AVG(fop.add_to_cart_order)::NUMERIC, 2) AS avg_cart_position,
    ROUND((COUNT(*) FILTER (WHERE fop.add_to_cart_order = 1)::NUMERIC / COUNT(*)::NUMERIC) * 100, 2) AS pct_first_item,
    ROUND((COUNT(*) FILTER (WHERE fop.reordered = 1)::NUMERIC / COUNT(*)::NUMERIC) * 100, 2)         AS reorder_rate_pct
FROM fact_order_products fop
JOIN dim_products    p ON fop.product_id  = p.product_id
JOIN dim_departments d ON p.department_id = d.department_id
JOIN dim_aisles      a ON p.aisle_id      = a.aisle_id
GROUP BY p.product_id, p.product_name, d.department, a.aisle
HAVING COUNT(*) >= 100;

CREATE INDEX idx_mv_product_purchases ON mv_product_basket_dynamics (total_purchases DESC);

-- ---------------------------------------------------------------------------
-- 2. Customer lifecycle: one definition (the view), one physical copy for Tableau.
--    Cohort logic lives here so it is reviewable, and uses the SAME rounded value as the
--    chart axis (cadence_day), which removes the split bars at days 8 and 21.
--    New columns are appended after the original ones so existing Tableau fields keep working.
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS mv_customer_segments;
DROP TABLE IF EXISTS mv_customer_lifecycle;
DROP VIEW  IF EXISTS v_customer_lifecycle;

CREATE VIEW v_customer_lifecycle AS
WITH base AS (
    SELECT
        user_id,
        COUNT(order_id) AS total_orders,
        ROUND(AVG(days_since_prior_order)::NUMERIC, 2) AS avg_inter_order_days,
        MIN(days_since_prior_order) AS min_inter_order_days,
        MAX(days_since_prior_order) AS max_inter_order_days,
        ROUND(AVG(days_since_prior_order))::INT AS cadence_day,
        ROUND(STDDEV_SAMP(days_since_prior_order)::NUMERIC, 2) AS sd_inter_order_days
    FROM fact_orders
    WHERE eval_set IN ('prior', 'train')
    GROUP BY user_id
)
SELECT
    base.*,
    CASE
        WHEN cadence_day >= 30 THEN 'Capped (30+ days)'          -- source caps gaps at 30
        WHEN cadence_day <= 8  THEN 'Weekly Habitual (1-8 days)'
        WHEN cadence_day <= 21 THEN 'Bi-Weekly (9-21 days)'
        ELSE                        'Monthly / Occasional (22-29 days)'
    END AS cadence_cohort
FROM base;

CREATE TABLE mv_customer_lifecycle AS
SELECT * FROM v_customer_lifecycle;

CREATE INDEX idx_mv_customer_orders ON mv_customer_lifecycle (total_orders DESC);

-- ---------------------------------------------------------------------------
-- 3. Customer regularity: how consistent is each customer's gap, compared with peers of similar cadence?
--    cv = std dev of gaps / mean gap (lower = more regular).
--    Why tiers are RELATIVE (terciles of cv inside each cadence cohort) and not a fixed cut-off:
--    on real data the median cv was about 0.69 (Weekly), 0.62 (Bi-Weekly) and 0.34 (Monthly). A single
--    threshold such as 0.5 therefore sorts customers by cadence length, not by regularity, probably because the
--    source's 30-day cap compresses the spread of long-gap customers. Comparing a Weekly customer's cv with a
--    Monthly customer's cv is not valid, so tiers are only comparable within one cohort.
--    The 'Capped' cohort is not measurable: every gap sits at the ceiling, so cv is about 0 by construction.
-- ---------------------------------------------------------------------------
CREATE TABLE mv_customer_segments AS
WITH x AS (
    SELECT
        user_id, total_orders, avg_inter_order_days, sd_inter_order_days, cadence_cohort,
        ROUND(sd_inter_order_days / NULLIF(avg_inter_order_days, 0), 2) AS cv,
        COALESCE(cadence_cohort <> 'Capped (30+ days)'
                 AND total_orders >= 6
                 AND sd_inter_order_days IS NOT NULL
                 AND avg_inter_order_days > 0, FALSE) AS measurable
    FROM mv_customer_lifecycle
), t AS (
    -- rank only measurable customers against each other (measurable is part of the partition);
    -- ties on cv are broken by user_id so the three tiers are equal in size
    SELECT x.*,
           NTILE(3) OVER (PARTITION BY cadence_cohort, measurable ORDER BY cv, user_id) AS cv_tercile
    FROM x
)
SELECT
    user_id, total_orders, avg_inter_order_days, sd_inter_order_days, cadence_cohort, cv,
    CASE
        WHEN cadence_cohort = 'Capped (30+ days)' THEN 'Not measurable (capped)'
        WHEN NOT measurable                       THEN 'Insufficient history'
        WHEN cv_tercile = 1                       THEN 'More regular'
        WHEN cv_tercile = 2                       THEN 'Typical'
        ELSE                                           'Less regular'
    END AS regularity
FROM t;

CREATE INDEX idx_mv_customer_segments_user ON mv_customer_segments (user_id);

-- ---------------------------------------------------------------------------
-- 4. Product pairs (market-basket association) for the 200 highest-volume products.
--    Limited to 200 because an unrestricted self-join on ~33M line items would run for hours.
--    Pairs seen in fewer than 50 orders are dropped.
--    support = share of all orders containing both; confidence = P(B | A); lift = observed / expected.
-- ---------------------------------------------------------------------------
-- NOTE: product_a is simply the lower product_id of the pair, so 'a' is not an antecedent. Read BOTH confidence
-- columns; lift is symmetric and is the one number that does not depend on the A/B labelling.
CREATE TABLE mv_product_pairs AS
WITH top_products AS (
    SELECT product_id
    FROM mv_product_basket_dynamics
    ORDER BY total_purchases DESC
    LIMIT 200
), b AS (
    SELECT fop.order_id, fop.product_id
    FROM fact_order_products fop
    JOIN top_products t USING (product_id)
), tot AS (
    SELECT COUNT(*)::NUMERIC AS n FROM fact_orders WHERE eval_set <> 'test'   -- orders that have items
), single AS (
    SELECT product_id, COUNT(*)::NUMERIC AS cnt FROM b GROUP BY product_id
), pairs AS (
    SELECT a.product_id AS p1, c.product_id AS p2, COUNT(*)::NUMERIC AS pair_cnt
    FROM b a
    JOIN b c ON a.order_id = c.order_id AND a.product_id < c.product_id
    GROUP BY a.product_id, c.product_id
    HAVING COUNT(*) >= 50
)
SELECT
    p1.product_name AS product_a,
    a1.aisle        AS aisle_a,
    p2.product_name AS product_b,
    a2.aisle        AS aisle_b,
    pairs.pair_cnt,
    ROUND(100 * pairs.pair_cnt / tot.n, 3)                 AS support_pct,
    ROUND(100 * pairs.pair_cnt / s1.cnt, 2)                AS confidence_a_to_b_pct,
    ROUND(100 * pairs.pair_cnt / s2.cnt, 2)                AS confidence_b_to_a_pct,
    ROUND((pairs.pair_cnt * tot.n) / (s1.cnt * s2.cnt), 2) AS lift
FROM pairs
CROSS JOIN tot
JOIN single      s1 ON s1.product_id = pairs.p1
JOIN single      s2 ON s2.product_id = pairs.p2
JOIN dim_products p1 ON p1.product_id = pairs.p1
JOIN dim_products p2 ON p2.product_id = pairs.p2
JOIN dim_aisles  a1 ON a1.aisle_id   = p1.aisle_id
JOIN dim_aisles  a2 ON a2.aisle_id   = p2.aisle_id;

CREATE INDEX idx_mv_product_pairs_lift ON mv_product_pairs (lift DESC);

-- ---------------------------------------------------------------------------
-- 5. Workload by weekly time slot (all 168 day x hour slots, including empty ones).
--    Uses ITEMS as well as orders: picking effort scales with items, not order count.
--    The dataset has no calendar dates, so loads are RELATIVE (100 = the average slot),
--    never absolute headcount. Only orders with line items (prior + train) are included.
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS mv_slot_workload;

CREATE TABLE mv_slot_workload AS
WITH order_size AS (
    SELECT order_id, COUNT(*) AS items
    FROM fact_order_products
    GROUP BY order_id
), slots AS (
    SELECT o.order_dow, o.order_hour_of_day,
           COUNT(*)     AS orders,
           SUM(s.items) AS items
    FROM fact_orders o
    JOIN order_size s USING (order_id)
    GROUP BY o.order_dow, o.order_hour_of_day
), grid AS (
    SELECT d.dow AS order_dow, h.hr AS order_hour_of_day,
           COALESCE(s.orders, 0) AS orders,
           COALESCE(s.items, 0)  AS items
    FROM generate_series(0, 6)  AS d(dow)
    CROSS JOIN generate_series(0, 23) AS h(hr)
    LEFT JOIN slots s ON s.order_dow = d.dow AND s.order_hour_of_day = h.hr
)
SELECT
    order_dow,
    order_hour_of_day,
    orders,
    items,
    ROUND(items::NUMERIC / NULLIF(orders, 0), 2)                 AS avg_items_per_order,
    ROUND(100.0 * orders / NULLIF(AVG(orders) OVER (), 0), 1)    AS order_load_index,
    ROUND(100.0 * items  / NULLIF(AVG(items)  OVER (), 0), 1)    AS item_load_index
FROM grid;

CREATE INDEX idx_mv_slot_workload_items ON mv_slot_workload (items DESC);

ANALYZE;
