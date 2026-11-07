-- 07_insights.sql : read-only queries that answer business questions. Nothing here builds tables.
-- Every number you quote in the README should come from one of these queries.

-- 7.1 Which products start baskets? (anchor / gateway items, volume >= 1,000)
SELECT product_name, department, total_purchases, pct_first_item, reorder_rate_pct
FROM mv_product_basket_dynamics
WHERE total_purchases >= 1000
ORDER BY pct_first_item DESC
LIMIT 15;

-- 7.2 Department mix and loyalty
SELECT d.department,
       COUNT(*)                                            AS items,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)  AS pct_of_items,
       ROUND(100.0 * AVG(fop.reordered), 2)                AS reorder_rate_pct,
       ROUND(AVG(fop.add_to_cart_order), 2)                AS avg_cart_pos
FROM fact_order_products fop
JOIN dim_products    p USING (product_id)
JOIN dim_departments d USING (department_id)
GROUP BY d.department
ORDER BY items DESC;

-- 7.3 Pareto: how concentrated is demand across the catalog? (assortment / slotting)
WITH p AS (
    SELECT product_id, COUNT(*) AS n
    FROM fact_order_products
    GROUP BY product_id
), r AS (
    SELECT n,
           SUM(n) OVER (ORDER BY n DESC, product_id)       AS cum,
           SUM(n) OVER ()                                  AS tot,
           ROW_NUMBER() OVER (ORDER BY n DESC, product_id) AS rn,
           COUNT(*) OVER ()                                AS cnt
    FROM p
)
SELECT MIN(rn) FILTER (WHERE cum >= 0.5 * tot) AS products_for_50pct_of_volume,
       MIN(rn) FILTER (WHERE cum >= 0.8 * tot) AS products_for_80pct_of_volume,
       MAX(cnt)                                AS total_products
FROM r;

-- 7.4 Order-size distribution (items per order drives picking workload)
WITH order_size AS (
    SELECT order_id, COUNT(*) AS items
    FROM fact_order_products
    GROUP BY order_id
)
SELECT ROUND(AVG(items), 1)                                         AS avg_items,
       percentile_cont(0.5)  WITHIN GROUP (ORDER BY items)          AS p50_items,
       percentile_cont(0.9)  WITHIN GROUP (ORDER BY items)          AS p90_items,
       percentile_cont(0.99) WITHIN GROUP (ORDER BY items)          AS p99_items,
       ROUND(100.0 * COUNT(*) FILTER (WHERE items >= 30) / COUNT(*), 2) AS pct_orders_30plus_items
FROM order_size;

-- 7.5 Does behaviour change as customers mature? (scans every line item; allow time on the full data)
SELECT o.order_number,
       ROUND(AVG(o.days_since_prior_order), 2) AS avg_gap_days,
       ROUND(100.0 * AVG(fop.reordered), 2)    AS reorder_rate_pct
FROM fact_orders o
JOIN fact_order_products fop USING (order_id)
WHERE o.order_number BETWEEN 2 AND 30
GROUP BY o.order_number
ORDER BY o.order_number;

-- 7.6 Cadence cohort x regularity tier. Tiers are terciles of cv WITHIN each cohort (see 05), so each
--     measurable cohort splits about 1/3 each by construction; use this to size the groups, not to compare cohorts.
SELECT cadence_cohort,
       regularity,
       COUNT(*) AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY cadence_cohort), 2) AS pct_of_cohort
FROM mv_customer_segments
GROUP BY cadence_cohort, regularity
ORDER BY MIN(avg_inter_order_days), regularity;

-- 7.6b Spread of cv by cohort: the evidence behind the tiering (box-plot numbers)
SELECT cadence_cohort,
       COUNT(*) AS customers,
       ROUND((percentile_cont(0.25) WITHIN GROUP (ORDER BY cv::float8))::NUMERIC, 2) AS p25_cv,
       ROUND((percentile_cont(0.50) WITHIN GROUP (ORDER BY cv::float8))::NUMERIC, 2) AS median_cv,
       ROUND((percentile_cont(0.75) WITHIN GROUP (ORDER BY cv::float8))::NUMERIC, 2) AS p75_cv
FROM mv_customer_segments
WHERE regularity NOT IN ('Insufficient history', 'Not measurable (capped)')
GROUP BY cadence_cohort
ORDER BY MIN(avg_inter_order_days);

-- 7.7 Cross-aisle product pairs with the strongest association (real cross-sell candidates;
--     same-aisle pairs are mostly near-duplicate variants, e.g. two kinds of bananas)
SELECT product_a, aisle_a, product_b, aisle_b, pair_cnt, support_pct,
       confidence_a_to_b_pct, confidence_b_to_a_pct, lift
FROM mv_product_pairs
WHERE aisle_a <> aisle_b
ORDER BY lift DESC
LIMIT 20;
