-- 08_workload_analysis.sql : staffing-oriented reads of mv_slot_workload (built in 05).
-- Loads are RELATIVE (100 = the average of the 168 weekly slots); the data has no calendar dates,
-- so none of this converts to absolute headcount without outside assumptions.

-- 8.1 Top 25 slots by picking workload (items), with cumulative share of all items
SELECT order_dow, order_hour_of_day, orders, items, avg_items_per_order,
       order_load_index, item_load_index,
       ROUND(100.0 * SUM(items) OVER (ORDER BY items DESC, order_dow, order_hour_of_day)
                   / SUM(items) OVER (), 1) AS cum_pct_of_items
FROM mv_slot_workload
ORDER BY items DESC, order_dow, order_hour_of_day
LIMIT 25;

-- 8.2 Concentration: how many of the 168 slots carry half / four-fifths of the workload?
WITH r AS (
    SELECT SUM(items) OVER (ORDER BY items DESC, order_dow, order_hour_of_day) AS cum,
           SUM(items) OVER ()                                                  AS tot,
           ROW_NUMBER() OVER (ORDER BY items DESC, order_dow, order_hour_of_day) AS rn
    FROM mv_slot_workload
)
SELECT MIN(rn) FILTER (WHERE cum >= 0.5 * tot) AS slots_for_50pct_of_items,
       MIN(rn) FILTER (WHERE cum >= 0.8 * tot) AS slots_for_80pct_of_items
FROM r;

-- 8.3 Peak-to-average and peak-to-median ratios (capacity sizing).
--     Median, not minimum: the quietest overnight slot can hold a handful of orders, which makes
--     a peak-to-trough ratio huge and meaningless.
SELECT ROUND(MAX(item_load_index) / 100.0, 2)                                       AS peak_to_average,
       ROUND(MAX(items)::NUMERIC / NULLIF(percentile_cont(0.5) WITHIN GROUP (ORDER BY items)::NUMERIC, 0), 2)
                                                                                    AS peak_to_median
FROM mv_slot_workload;

-- 8.4 Where does counting orders mislead? Slots whose rank changes most once order size is considered
WITH r AS (
    SELECT *,
           RANK() OVER (ORDER BY orders DESC) AS order_rank,
           RANK() OVER (ORDER BY items  DESC) AS item_rank
    FROM mv_slot_workload
)
SELECT order_dow, order_hour_of_day, orders, items, avg_items_per_order,
       order_rank, item_rank, order_rank - item_rank AS rank_gain_when_weighted_by_items
FROM r
WHERE LEAST(order_rank, item_rank) <= 30
ORDER BY ABS(order_rank - item_rank) DESC, item_rank
LIMIT 10;

-- 8.5 Daypart profile (share of weekly items by block of the day)
SELECT CASE
           WHEN order_hour_of_day BETWEEN 0  AND 5  THEN '1) 00-05 overnight'
           WHEN order_hour_of_day BETWEEN 6  AND 8  THEN '2) 06-08 early'
           WHEN order_hour_of_day BETWEEN 9  AND 16 THEN '3) 09-16 core'
           WHEN order_hour_of_day BETWEEN 17 AND 20 THEN '4) 17-20 evening'
           ELSE                                          '5) 21-23 late'
       END AS daypart,
       SUM(orders) AS orders,
       SUM(items)  AS items,
       ROUND(100.0 * SUM(items) / SUM(SUM(items)) OVER (), 1) AS pct_of_items
FROM mv_slot_workload
GROUP BY 1
ORDER BY 1;
