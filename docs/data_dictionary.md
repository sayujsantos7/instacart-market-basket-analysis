# Data dictionary

## Raw tables (loaded from the Kaggle CSVs)

| Table | Grain | Notes |
|-------|-------|-------|
| `dim_aisles`, `dim_departments` | one row per aisle / department | |
| `dim_products` | product | links to aisle and department |
| `fact_orders` | order | `eval_set` is `prior`, `train` or `test`. `order_dow` 0-6 (day names undocumented). `order_hour_of_day` 0-23. `days_since_prior_order` is NULL on a customer's first order and capped at 30. |
| `fact_order_products` | order x product | `add_to_cart_order` is the position in the cart; `reordered` is 1 if the customer had bought the product before. Holds `prior` + `train` orders; `test` orders have no items. |

## Summary tables (built by `sql/05_analytics_layer.sql`)

### mv_product_basket_dynamics (products with >= 100 purchases)
| Column | Meaning |
|--------|---------|
| `total_purchases` | number of order lines containing the product |
| `avg_cart_position` | mean `add_to_cart_order` |
| `pct_first_item` | % of purchases where the product was added first |
| `reorder_rate_pct` | % of purchases flagged `reordered = 1` |

### mv_customer_lifecycle (one row per customer, `prior` + `train` orders)
| Column | Meaning |
|--------|---------|
| `total_orders` | orders counted (excludes the customer's `test` order) |
| `avg_inter_order_days` | mean of `days_since_prior_order` (first order's NULL ignored) |
| `min_/max_inter_order_days` | smallest / largest gap |
| `cadence_day` | `avg_inter_order_days` rounded to a whole day (chart x-axis) |
| `sd_inter_order_days` | sample standard deviation of the gaps |
| `cadence_cohort` | Weekly Habitual (1-8), Bi-Weekly (9-21), Monthly / Occasional (22-29), Capped (30), all on `cadence_day` |

### mv_customer_segments
Adds `cv` (= `sd_inter_order_days / avg_inter_order_days`; lower = more regular) and `regularity`:
*Not measurable (capped)* (Capped cohort: every gap is the 30-day ceiling), *Insufficient history* (under 6 orders or no `cv`),
otherwise *More regular* / *Typical* / *Less regular* = lower / middle / upper third of `cv` among measurable customers **in the same cohort**.
Tiers are comparable only within a cohort. A fixed cut-off was rejected because median `cv` differs strongly by cohort (about 0.69 Weekly, 0.62 Bi-Weekly, 0.34 Monthly on the real data), so it would sort customers by cadence length.

### mv_product_pairs (200 highest-volume products, pairs in >= 50 orders)
| Column | Meaning |
|--------|---------|
| `support_pct` | % of all orders (with items) containing both products |
| `confidence_a_to_b_pct`, `confidence_b_to_a_pct` | of orders containing A, the % that also contain B (and the reverse). `product_a` is just the lower product_id, so it is not an antecedent; read both columns |
| `lift` | observed co-occurrence / co-occurrence expected if independent. 1 = no association; above 1 = bought together more often than chance |

### mv_slot_workload (168 rows: 7 day codes x 24 hours, empty slots included)
| Column | Meaning |
|--------|---------|
| `orders`, `items` | orders and order lines in the slot (`prior` + `train` orders) |
| `avg_items_per_order` | items / orders |
| `order_load_index`, `item_load_index` | slot value / average slot x 100. 100 = an average slot, 300 = three times average. Relative only: the data has no calendar dates. |
