# Data

Raw data is **not** committed (several hundred MB).

1. Download *Instacart Market Basket Analysis* from Kaggle: https://www.kaggle.com/c/instacart-market-basket-analysis/data
2. Unzip the CSVs into one folder.
3. Load them:
   - Command line: `DATA_DIR=/path/to/folder ./run_all.sh` (uses `sql/02_load.sql`; the folder must be readable by the PostgreSQL server, and your role needs superuser or `pg_read_server_files`).
   - pgAdmin / GUI: edit the six paths in `sql/02b_load_pgadmin.sql`, then run the SQL files in numeric order.

Expected files: `aisles.csv`, `departments.csv`, `products.csv`, `orders.csv`,
`order_products__prior.csv`, `order_products__train.csv`.
