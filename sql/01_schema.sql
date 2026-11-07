-- 01_schema.sql : tables for the Instacart schema (PostgreSQL 14+)
-- Safe to re-run: drops and recreates the raw tables (and any views that depend on them).

DROP TABLE IF EXISTS fact_order_products, fact_orders, dim_products, dim_departments, dim_aisles CASCADE;

CREATE TABLE dim_aisles (
    aisle_id INT PRIMARY KEY,
    aisle    VARCHAR(255) NOT NULL
);

CREATE TABLE dim_departments (
    department_id INT PRIMARY KEY,
    department    VARCHAR(255) NOT NULL
);

CREATE TABLE dim_products (
    product_id    INT PRIMARY KEY,
    product_name  TEXT NOT NULL,
    aisle_id      INT REFERENCES dim_aisles(aisle_id),
    department_id INT REFERENCES dim_departments(department_id)
);

CREATE TABLE fact_orders (
    order_id               INT PRIMARY KEY,
    user_id                INT NOT NULL,
    eval_set               VARCHAR(10) NOT NULL,   -- prior | train | test
    order_number           INT NOT NULL,
    order_dow              SMALLINT NOT NULL,      -- 0-6; the source does NOT say which day 0 is (see README)
    order_hour_of_day      SMALLINT NOT NULL,      -- 0-23
    days_since_prior_order NUMERIC(5,1)            -- NULL on a user's first order; capped at 30 in the source
);

CREATE TABLE fact_order_products (
    order_id          INT,
    product_id        INT REFERENCES dim_products(product_id),
    add_to_cart_order INT NOT NULL,
    reordered         SMALLINT NOT NULL,
    PRIMARY KEY (order_id, product_id)
);
