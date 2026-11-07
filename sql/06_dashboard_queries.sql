-- 06_dashboard_queries.sql : checks on the summary layer + the heatmap source query.

-- Top 10 products by volume (gateway-product check)
SELECT product_name, department, total_purchases, pct_first_item, reorder_rate_pct
FROM mv_product_basket_dynamics
ORDER BY total_purchases DESC
LIMIT 10;

-- Heatmap source (used as Custom SQL in the Tableau workbook).
-- Counts ALL orders, including 'test' orders (their timing is known even though items are withheld).
-- mv_slot_workload (item-weighted, prior + train only) is the better source for staffing questions.
SELECT order_dow, order_hour_of_day, COUNT(*) AS order_count
FROM fact_orders
GROUP BY order_dow, order_hour_of_day
ORDER BY order_dow, order_hour_of_day;

-- Cohort sizes as they will appear on the lifecycle chart
SELECT cadence_cohort, COUNT(*) AS customers
FROM mv_customer_lifecycle
GROUP BY cadence_cohort
ORDER BY MIN(cadence_day);
