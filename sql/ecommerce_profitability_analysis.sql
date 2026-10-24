/* =====================================================================
   E-COMMERCE PROFITABILITY ANALYSIS
   Author : Faizah Azam Raisa
   Tools  : MySQL 8.0 (analysis) · Tableau Public (dashboard)
   Data   : E-Commerce Sales Dataset (Kaggle)

   Business question:
     Which regions, customers, products and channels drive profit,
     and where is the company leaving money on the table?

   Tables:
     ecommerce_sales        raw order-level data (as imported)
     ecommerce_sales_clean  cleaned order-level data (created below)
     product_catalog        one row per product
     order_items            one row per product within an order

   Sections:
     0. Setup
     1. Data exploration
     2. Data quality checks
     3. Data cleaning
     4. Loading product and order-item tables
     5. Headline KPIs
     6. Regional analysis
     7. Profit opportunity sizing
     8. Customer analysis
     9. Marketing channel analysis
    10. Returns analysis
    11. Product analysis
    12. Export for Tableau
   ===================================================================== */


-- =====================================================================
-- 0. SETUP
-- =====================================================================
USE ecommerce_project;


-- =====================================================================
-- 1. DATA EXPLORATION (raw table)
-- =====================================================================

-- Unique customers
SELECT COUNT(DISTINCT customer_id) AS unique_customers
FROM ecommerce_sales;
-- Result: 24,911

-- Unique orders
SELECT COUNT(DISTINCT order_id) AS unique_orders
FROM ecommerce_sales;
-- Result: 138,116

-- Regions
SELECT DISTINCT region
FROM ecommerce_sales;
-- Result: North, South, East, West, Central

-- Customer segments
SELECT DISTINCT customer_segment
FROM ecommerce_sales;
-- Result: Consumer, Premium, VIP, Business

-- Marketing channels
SELECT DISTINCT marketing_channel
FROM ecommerce_sales;
-- Result: Direct, YouTube, Email Marketing, Organic Search, Referral,
--         Google Ads, Facebook Ads, TikTok, Instagram, Affiliate

-- Return status values
SELECT DISTINCT return_status
FROM ecommerce_sales;


-- =====================================================================
-- 2. DATA QUALITY CHECKS
-- =====================================================================

-- Missing values in key columns (blank strings in the raw import)
SELECT
    COUNT(*)                                                     AS total_records,
    SUM(CASE WHEN net_sales         = '' THEN 1 ELSE 0 END)      AS missing_sales,
    SUM(CASE WHEN profit            = '' THEN 1 ELSE 0 END)      AS missing_profit,
    SUM(CASE WHEN region            = '' THEN 1 ELSE 0 END)      AS missing_region,
    SUM(CASE WHEN marketing_channel = '' THEN 1 ELSE 0 END)      AS missing_marketing_channel,
    SUM(CASE WHEN delivery_days     = '' THEN 1 ELSE 0 END)      AS missing_delivery_days,
    SUM(CASE WHEN customer_rating   = '' THEN 1 ELSE 0 END)      AS missing_customer_rating
FROM ecommerce_sales;

-- Do missing delivery days and missing ratings occur on the same orders?
-- (Undelivered orders cannot be rated, so these should overlap.)
SELECT COUNT(*) AS records_missing_both
FROM ecommerce_sales
WHERE delivery_days = ''
  AND customer_rating = '';

-- Inspect values before casting to numeric types
SELECT DISTINCT delivery_days
FROM ecommerce_sales
WHERE delivery_days <> ''
LIMIT 20;

SELECT DISTINCT customer_rating
FROM ecommerce_sales
WHERE customer_rating <> ''
LIMIT 20;


-- =====================================================================
-- 3. DATA CLEANING
--    - Converts blank strings to NULL (NULLIF)
--    - Casts text columns to proper numeric types
--    - Standardizes return_status
-- =====================================================================

DROP TABLE IF EXISTS ecommerce_sales_clean;

CREATE TABLE ecommerce_sales_clean AS
SELECT
    -- IDs
    order_id,
    customer_id,

    -- Customer attributes
    customer_name,
    customer_segment,
    customer_type,
    gender,
    region,
    customer_city,
    customer_state,
    customer_country,

    -- Marketing
    marketing_channel,

    -- Order status
    order_status,
    return_status,
    return_reason,

    -- Customer metrics
    CAST(NULLIF(customer_age, '')            AS UNSIGNED)       AS customer_age,
    CAST(NULLIF(customer_rating, '')         AS DECIMAL(3,1))   AS customer_rating,
    CAST(NULLIF(customer_lifetime_value, '') AS DECIMAL(12,2))  AS customer_lifetime_value,
    is_repeat_customer,
    CAST(NULLIF(customer_order_count, '')    AS UNSIGNED)       AS customer_order_count,

    -- Delivery metrics
    CAST(NULLIF(delivery_days, '')           AS DECIMAL(5,1))   AS delivery_days,
    CAST(NULLIF(estimated_delivery_days, '') AS DECIMAL(5,1))   AS estimated_delivery_days,
    delivery_status,

    -- Financial metrics
    CAST(NULLIF(gross_sales, '')             AS DECIMAL(12,2))  AS gross_sales,
    CAST(NULLIF(discount_amount, '')         AS DECIMAL(12,2))  AS discount_amount,
    CAST(NULLIF(tax_amount, '')              AS DECIMAL(12,2))  AS tax_amount,
    CAST(NULLIF(shipping_cost, '')           AS DECIMAL(12,2))  AS shipping_cost,
    CAST(NULLIF(net_sales, '')               AS DECIMAL(12,2))  AS net_sales,
    CAST(NULLIF(product_cost, '')            AS DECIMAL(12,2))  AS product_cost,
    CAST(NULLIF(profit, '')                  AS DECIMAL(12,2))  AS profit,
    CAST(NULLIF(profit_margin_percentage, '') AS DECIMAL(10,2)) AS profit_margin_percentage,
    CAST(NULLIF(quantity, '')                AS UNSIGNED)       AS quantity
FROM ecommerce_sales;

-- Standardize return_status: blank / NULL means the order was not returned
UPDATE ecommerce_sales_clean
SET return_status = 'Not Returned'
WHERE return_status IS NULL
   OR return_status = '';

-- Verify the cleaned table
DESCRIBE ecommerce_sales_clean;

SELECT return_status, COUNT(*) AS orders
FROM ecommerce_sales_clean
GROUP BY return_status;

-- Row count should match the raw table
SELECT
    (SELECT COUNT(*) FROM ecommerce_sales)       AS raw_rows,
    (SELECT COUNT(*) FROM ecommerce_sales_clean) AS clean_rows;


-- =====================================================================
-- 4. LOADING PRODUCT AND ORDER-ITEM TABLES
--    Files must sit in MySQL's secure_file_priv folder:
--    SHOW VARIABLES LIKE 'secure_file_priv';
-- =====================================================================

-- Product catalog
DROP TABLE IF EXISTS product_catalog;

CREATE TABLE product_catalog (
    product_id          VARCHAR(20) PRIMARY KEY,
    product_name        VARCHAR(255),
    product_category    VARCHAR(100),
    product_subcategory VARCHAR(100),
    brand               VARCHAR(100),
    supplier            VARCHAR(100),
    unit_price          DECIMAL(10,2),
    product_cost        DECIMAL(10,2),
    product_rating      DECIMAL(3,1)
);

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/product_catalog.csv'
INTO TABLE product_catalog
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT COUNT(*) AS total_products
FROM product_catalog;

-- Order items
DROP TABLE IF EXISTS order_items;

CREATE TABLE order_items (
    order_id            VARCHAR(50),
    product_id          VARCHAR(20),
    quantity            INT,
    unit_price          DECIMAL(10,2),
    discount_percentage DECIMAL(12,10),
    discount_amount     DECIMAL(10,2),
    gross_sales         DECIMAL(12,2),
    tax_amount          DECIMAL(10,2),
    shipping_cost       DECIMAL(10,2),
    net_sales           DECIMAL(12,2),
    product_cost        DECIMAL(12,2),
    profit              DECIMAL(12,2)
);

LOAD DATA INFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/order_items.csv'
INTO TABLE order_items
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

SELECT COUNT(*) AS total_order_items
FROM order_items;

-- Every order item should match a product in the catalog
SELECT
    COUNT(*)            AS order_item_rows,
    COUNT(pc.product_id) AS matched_rows
FROM order_items oi
LEFT JOIN product_catalog pc
       ON oi.product_id = pc.product_id;


-- =====================================================================
-- 5. HEADLINE KPIs (match the dashboard KPI row)
-- =====================================================================

SELECT
    ROUND(SUM(net_sales), 2)                                     AS revenue,
    ROUND(SUM(profit), 2)                                        AS profit,
    ROUND(SUM(profit) / SUM(net_sales) * 100, 2)                 AS profit_margin_pct,
    COUNT(DISTINCT order_id)                                     AS orders,
    ROUND(SUM(net_sales) / COUNT(DISTINCT order_id), 2)          AS avg_order_value,
    COUNT(DISTINCT customer_id)                                  AS customers,
    ROUND(SUM(CASE WHEN return_status = 'Returned' THEN 1 ELSE 0 END)
          / COUNT(DISTINCT order_id) * 100, 2)                   AS return_rate_pct
FROM ecommerce_sales_clean;
-- Result: $177.13M revenue · $76.15M profit · 42.99% margin · 138,116 orders
--         $1,283 AOV · 24,911 customers · 6.9% return rate


-- =====================================================================
-- 6. REGIONAL ANALYSIS
--    Question: South earns the most revenue, so why does North/West
--    keep more of each dollar?
-- =====================================================================

-- 6.1 Revenue, profit and margin by region
SELECT
    region,
    ROUND(SUM(net_sales), 2)                     AS revenue,
    ROUND(SUM(profit), 2)                        AS profit,
    ROUND(SUM(profit) / SUM(net_sales) * 100, 2) AS profit_margin_pct
FROM ecommerce_sales_clean
GROUP BY region
ORDER BY profit_margin_pct DESC;
-- Finding: South leads revenue ($55.59M) but has one of the lowest margins (41.99%).
--          North (46.10%) and West (45.02%) are the most efficient.

-- 6.2 Cost structure: where does each sales dollar go?
SELECT
    region,
    ROUND(SUM(product_cost)  / SUM(net_sales) * 100, 2) AS product_cost_pct,
    ROUND(SUM(shipping_cost) / SUM(net_sales) * 100, 2) AS shipping_pct,
    ROUND(SUM(profit)        / SUM(net_sales) * 100, 2) AS profit_margin_pct
FROM ecommerce_sales_clean
GROUP BY region
ORDER BY profit_margin_pct DESC;
-- Result:  North 52.38 / 1.52 / 46.10
--          West  53.40 / 1.58 / 45.02
--          South 56.20 / 1.80 / 41.99
--          Central 56.30 / 1.81 / 41.90
--          East  56.78 / 1.90 / 41.32
-- Finding: Product cost explains over 90% of the margin gap
--          (North vs East: 4.40 of 4.78 points). Shipping explains < 0.4 points.

-- 6.3 Shipping cost as a share of sales (hypothesis: shipping drives the gap)
SELECT
    region,
    ROUND(AVG(shipping_cost), 2)                        AS avg_shipping_cost,
    ROUND(SUM(shipping_cost), 2)                        AS total_shipping_cost,
    ROUND(SUM(shipping_cost) / SUM(net_sales) * 100, 2) AS shipping_pct_of_sales,
    ROUND(SUM(profit) / SUM(net_sales) * 100, 2)        AS profit_margin_pct
FROM ecommerce_sales_clean
GROUP BY region
ORDER BY profit_margin_pct DESC;
-- Finding: Shipping is only ~1.5-1.9% of sales in every region. Ruled out.

-- 6.4 Discounts by region (hypothesis: heavier discounting lowers margin)
SELECT
    region,
    ROUND(AVG(discount_amount), 2)               AS avg_discount,
    ROUND(SUM(profit) / SUM(net_sales) * 100, 2) AS profit_margin_pct
FROM ecommerce_sales_clean
GROUP BY region
ORDER BY avg_discount DESC;

-- 6.5 Product mix by region (hypothesis: low-margin regions sell more Electronics)
SELECT
    e.region,
    ROUND(SUM(CASE WHEN pc.product_category = 'Electronics' THEN oi.net_sales ELSE 0 END)
          / SUM(oi.net_sales) * 100, 2)                  AS electronics_share_pct,
    ROUND(SUM(oi.product_cost) / SUM(oi.net_sales) * 100, 2) AS item_cost_pct
FROM order_items oi
JOIN product_catalog pc       ON oi.product_id = pc.product_id
JOIN ecommerce_sales_clean e  ON oi.order_id  = e.order_id
GROUP BY e.region
ORDER BY item_cost_pct DESC;
-- Finding: Electronics is ~21% of sales in every region, so product mix
--          does not explain the gap. The same products cost more in S/C/E.

-- 6.6 Customer satisfaction by region (hypothesis: happier customers = higher margin)
SELECT
    region,
    ROUND(AVG(customer_rating), 2)               AS avg_rating,
    ROUND(SUM(profit) / SUM(net_sales) * 100, 2) AS profit_margin_pct
FROM ecommerce_sales_clean
WHERE customer_rating IS NOT NULL
GROUP BY region
ORDER BY avg_rating DESC;

-- 6.7 Return rate by region (hypothesis: returns drag down margin)
SELECT
    region,
    COUNT(*)                                                         AS total_orders,
    SUM(CASE WHEN return_status = 'Returned' THEN 1 ELSE 0 END)      AS returned_orders,
    ROUND(SUM(CASE WHEN return_status = 'Returned' THEN 1 ELSE 0 END)
          * 100 / COUNT(*), 2)                                       AS return_rate_pct
FROM ecommerce_sales_clean
GROUP BY region
ORDER BY return_rate_pct DESC;


-- =====================================================================
-- 7. PROFIT OPPORTUNITY SIZING
--    If South, Central and East paid the same product cost rate as
--    North/West, how much more profit would they keep?
--    Assumes revenue stays constant -> upper-bound estimate.
-- =====================================================================

WITH region_totals AS (
    SELECT
        region,
        SUM(net_sales)    AS sales,
        SUM(product_cost) AS cost
    FROM ecommerce_sales_clean
    GROUP BY region
),
benchmark AS (
    SELECT SUM(cost) / SUM(sales) AS benchmark_rate   -- North + West combined
    FROM region_totals
    WHERE region IN ('North', 'West')
)
SELECT
    r.region,
    ROUND(r.cost / r.sales * 100, 2)                         AS product_cost_pct,
    ROUND(b.benchmark_rate * 100, 2)                         AS benchmark_pct,
    ROUND((r.cost / r.sales - b.benchmark_rate) * 100, 2)    AS gap_pts,
    ROUND((r.cost / r.sales - b.benchmark_rate) * r.sales, 0) AS profit_opportunity
FROM region_totals r
CROSS JOIN benchmark b
WHERE r.region IN ('South', 'Central', 'East')
ORDER BY profit_opportunity DESC;
-- Expected: benchmark ~53.0%; South ~$1.78M, Central ~$1.23M, East ~$1.02M
--           Total ~ $4.0M

-- Total opportunity in one number
WITH region_totals AS (
    SELECT region, SUM(net_sales) AS sales, SUM(product_cost) AS cost
    FROM ecommerce_sales_clean
    GROUP BY region
),
benchmark AS (
    SELECT SUM(cost) / SUM(sales) AS benchmark_rate
    FROM region_totals
    WHERE region IN ('North', 'West')
)
SELECT ROUND(SUM((r.cost / r.sales - b.benchmark_rate) * r.sales), 0) AS total_profit_opportunity
FROM region_totals r
CROSS JOIN benchmark b
WHERE r.region IN ('South', 'Central', 'East');


-- =====================================================================
-- 8. CUSTOMER ANALYSIS
--    NOTE: customer_lifetime_value repeats on every order a customer
--    places. Averaging it at order level over-weights frequent buyers,
--    so CLV is calculated at CUSTOMER level (one row per customer).
-- =====================================================================

-- 8.0 Check: are customer attributes constant across a customer's orders?
--     Expected: 0 rows with conflicting values.
SELECT COUNT(*) AS customers_with_conflicts
FROM (
    SELECT customer_id
    FROM ecommerce_sales_clean
    GROUP BY customer_id
    HAVING COUNT(DISTINCT customer_segment)        > 1
        OR COUNT(DISTINCT is_repeat_customer)      > 1
        OR COUNT(DISTINCT customer_lifetime_value) > 1
) AS conflicts;

-- 8.1 Segment: revenue, profit, customers and orders
SELECT
    customer_segment,
    COUNT(DISTINCT customer_id)                  AS customers,
    COUNT(DISTINCT order_id)                     AS orders,
    ROUND(SUM(net_sales), 2)                     AS revenue,
    ROUND(SUM(profit), 2)                        AS profit,
    ROUND(SUM(profit) / SUM(net_sales) * 100, 2) AS profit_margin_pct
FROM ecommerce_sales_clean
GROUP BY customer_segment
ORDER BY revenue DESC;
-- Finding: Consumer has 54.5% of customers and 54.9% of revenue.
--          Every segment's revenue share ~ its customer share, so Consumer
--          leads because it has more customers, not because they spend more.

-- 8.2 Segment share of customers vs share of revenue
SELECT
    customer_segment,
    ROUND(COUNT(DISTINCT customer_id) * 100
          / (SELECT COUNT(DISTINCT customer_id) FROM ecommerce_sales_clean), 1) AS customer_share_pct,
    ROUND(SUM(net_sales) * 100
          / (SELECT SUM(net_sales) FROM ecommerce_sales_clean), 1)             AS revenue_share_pct
FROM ecommerce_sales_clean
GROUP BY customer_segment
ORDER BY revenue_share_pct DESC;

-- 8.3 Repeat vs one-time customers (customer level)
WITH customers AS (
    SELECT
        customer_id,
        MAX(is_repeat_customer)      AS is_repeat_customer,
        MAX(customer_lifetime_value) AS clv,
        MAX(customer_order_count)    AS order_count
    FROM ecommerce_sales_clean
    GROUP BY customer_id
)
SELECT
    is_repeat_customer,
    COUNT(*)                                          AS customers,
    ROUND(COUNT(*) * 100 / SUM(COUNT(*)) OVER (), 1)  AS customer_share_pct,
    ROUND(AVG(clv), 2)                                AS avg_clv,
    ROUND(AVG(order_count), 2)                        AS avg_orders
FROM customers
GROUP BY is_repeat_customer;
-- Expected: repeat 98.7% of customers, avg CLV ~$7,809 vs ~$1,304 (~6x).
-- Caveat: repeat customers have more orders by definition, so higher CLV
--         is partly mechanical. The bigger lever is order frequency and
--         basket size among existing repeat customers.

-- 8.4 Segment CLV and purchase behaviour (customer level)
WITH customers AS (
    SELECT
        customer_id,
        MAX(customer_segment)        AS customer_segment,
        MAX(customer_lifetime_value) AS clv,
        MAX(customer_order_count)    AS order_count
    FROM ecommerce_sales_clean
    GROUP BY customer_id
)
SELECT
    customer_segment,
    COUNT(*)                   AS customers,
    ROUND(AVG(clv), 2)         AS avg_clv,
    ROUND(AVG(order_count), 2) AS avg_orders
FROM customers
GROUP BY customer_segment
ORDER BY avg_clv DESC;

-- 8.5 Do higher-margin regions attract higher-value customers? (customer level)
WITH customers AS (
    SELECT
        customer_id,
        MAX(region)                  AS region,
        MAX(customer_lifetime_value) AS clv,
        MAX(customer_order_count)    AS order_count
    FROM ecommerce_sales_clean
    GROUP BY customer_id
)
SELECT
    region,
    COUNT(*)                   AS customers,
    ROUND(AVG(clv), 2)         AS avg_clv,
    ROUND(AVG(order_count), 2) AS avg_orders
FROM customers
GROUP BY region
ORDER BY avg_clv DESC;
-- Note: if a customer orders from more than one region, MAX(region)
--       picks one. Check with:
--       SELECT COUNT(*) FROM (SELECT customer_id FROM ecommerce_sales_clean
--       GROUP BY customer_id HAVING COUNT(DISTINCT region) > 1) t;

-- 8.6 Distribution of orders per customer
WITH customers AS (
    SELECT customer_id, MAX(customer_order_count) AS order_count
    FROM ecommerce_sales_clean
    GROUP BY customer_id
)
SELECT order_count, COUNT(*) AS customers
FROM customers
GROUP BY order_count
ORDER BY order_count;


-- =====================================================================
-- 9. MARKETING CHANNEL ANALYSIS
--    Question: Which channel deserves more budget?
-- =====================================================================

SELECT
    marketing_channel,
    COUNT(DISTINCT order_id)                     AS orders,
    ROUND(SUM(net_sales), 2)                     AS revenue,
    ROUND(SUM(profit), 2)                        AS profit,
    ROUND(SUM(profit) / SUM(net_sales) * 100, 2) AS profit_margin_pct
FROM ecommerce_sales_clean
GROUP BY marketing_channel
ORDER BY profit_margin_pct DESC;
-- Finding: Every channel earns 42.79%-43.19% margin. Channel does not drive
--          profitability, so budget should follow acquisition cost and
--          volume (not available in this dataset), not margin.


-- =====================================================================
-- 10. RETURNS ANALYSIS
--     Question: Are returns hurting profitability?
-- =====================================================================

-- 10.1 Orders, profit, average sale and average profit by return status
SELECT
    return_status,
    COUNT(*)                     AS orders,
    ROUND(SUM(profit), 2)        AS total_profit,
    ROUND(AVG(net_sales), 2)     AS avg_sale,
    ROUND(AVG(profit), 2)        AS avg_profit
FROM ecommerce_sales_clean
GROUP BY return_status;

-- 10.2 Return reasons
SELECT
    return_reason,
    COUNT(*) AS total_returns
FROM ecommerce_sales_clean
WHERE return_status = 'Returned'
GROUP BY return_reason
ORDER BY total_returns DESC;

-- 10.3 Return rate by customer segment
SELECT
    customer_segment,
    COUNT(*)                                                         AS total_orders,
    SUM(CASE WHEN return_status = 'Returned' THEN 1 ELSE 0 END)      AS returned_orders,
    ROUND(SUM(CASE WHEN return_status = 'Returned' THEN 1 ELSE 0 END)
          * 100 / COUNT(*), 2)                                       AS return_rate_pct
FROM ecommerce_sales_clean
GROUP BY customer_segment
ORDER BY return_rate_pct DESC;


-- =====================================================================
-- 11. PRODUCT ANALYSIS
-- =====================================================================

-- 11.1 Revenue, profit and margin by category
SELECT
    pc.product_category,
    ROUND(SUM(oi.net_sales), 2)                        AS revenue,
    ROUND(SUM(oi.profit), 2)                           AS profit,
    ROUND(SUM(oi.profit) / SUM(oi.net_sales) * 100, 2) AS profit_margin_pct
FROM order_items oi
JOIN product_catalog pc ON oi.product_id = pc.product_id
GROUP BY pc.product_category
ORDER BY revenue DESC;
-- Finding: The bigger the category, the thinner the margin.
--          Electronics leads sales at ~34% margin; Grocery earns ~55%.

-- 11.2 What drives the Electronics margin? Product cost vs discounting
SELECT
    pc.product_category,
    ROUND(SUM(oi.product_cost)    / SUM(oi.net_sales)   * 100, 2) AS product_cost_pct,
    ROUND(SUM(oi.discount_amount) / SUM(oi.gross_sales) * 100, 2) AS discount_pct_of_gross,
    ROUND(AVG(oi.discount_percentage) * 100, 2)                   AS avg_discount_pct,
    ROUND(SUM(oi.profit)          / SUM(oi.net_sales)   * 100, 2) AS profit_margin_pct
FROM order_items oi
JOIN product_catalog pc ON oi.product_id = pc.product_id
GROUP BY pc.product_category
ORDER BY profit_margin_pct;
-- Note: if avg_discount_pct looks 100x too large, discount_percentage is
--       already stored as a percentage; remove the "* 100".

-- 11.3 Top 15 brand-category combinations by profit, ranked
SELECT
    pc.brand,
    pc.product_category,
    ROUND(SUM(oi.net_sales), 2)                        AS revenue,
    ROUND(SUM(oi.profit), 2)                           AS profit,
    ROUND(SUM(oi.profit) / SUM(oi.net_sales) * 100, 2) AS profit_margin_pct,
    RANK() OVER (ORDER BY SUM(oi.profit) DESC)         AS profit_rank
FROM order_items oi
JOIN product_catalog pc ON oi.product_id = pc.product_id
GROUP BY pc.brand, pc.product_category
ORDER BY profit DESC
LIMIT 15;

-- 11.4 Worst-margin brand-category combinations (min $1M revenue)
SELECT
    pc.brand,
    pc.product_category,
    ROUND(SUM(oi.net_sales), 2)                        AS revenue,
    ROUND(SUM(oi.profit), 2)                           AS profit,
    ROUND(SUM(oi.profit) / SUM(oi.net_sales) * 100, 2) AS profit_margin_pct
FROM order_items oi
JOIN product_catalog pc ON oi.product_id = pc.product_id
GROUP BY pc.brand, pc.product_category
HAVING SUM(oi.net_sales) > 1000000
ORDER BY profit_margin_pct ASC
LIMIT 15;

-- 11.5 Top 15 individual products by profit margin
SELECT
    pc.product_name,
    pc.brand,
    pc.product_category,
    ROUND(SUM(oi.net_sales), 2)                        AS revenue,
    ROUND(SUM(oi.profit), 2)                           AS profit,
    ROUND(SUM(oi.profit) / SUM(oi.net_sales) * 100, 2) AS profit_margin_pct
FROM order_items oi
JOIN product_catalog pc ON oi.product_id = pc.product_id
GROUP BY pc.product_name, pc.brand, pc.product_category
ORDER BY profit_margin_pct DESC
LIMIT 15;


-- =====================================================================
-- 12. EXPORT FOR TABLEAU
--     Writes the clean table with a header row. LIMIT 200000 overrides
--     MySQL Workbench's default row limit (the table has fewer rows).
-- =====================================================================

SELECT 'order_id', 'customer_id', 'customer_name', 'customer_segment', 'customer_type',
       'gender', 'region', 'customer_city', 'customer_state', 'customer_country',
       'marketing_channel', 'order_status', 'return_status', 'return_reason',
       'customer_age', 'customer_rating', 'customer_lifetime_value', 'is_repeat_customer',
       'customer_order_count', 'delivery_days', 'estimated_delivery_days', 'delivery_status',
       'gross_sales', 'discount_amount', 'tax_amount', 'shipping_cost', 'net_sales',
       'product_cost', 'profit', 'profit_margin_percentage', 'quantity'
UNION ALL
SELECT *
FROM ecommerce_sales_clean
LIMIT 200000
INTO OUTFILE 'C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/ecommerce_sales_clean.csv'
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n';

-- Is the regional gap higher costs or lower prices?
SELECT
    e.region,
    ROUND(SUM(oi.product_cost) / SUM(oi.quantity), 2) AS cost_per_unit,
    ROUND(SUM(oi.gross_sales)  / SUM(oi.quantity), 2) AS list_price_per_unit,
    ROUND(SUM(oi.net_sales)    / SUM(oi.quantity), 2) AS net_price_per_unit,
    ROUND(SUM(oi.product_cost) / SUM(oi.net_sales) * 100, 2) AS product_cost_pct
FROM order_items oi
JOIN ecommerce_sales_clean e ON oi.order_id = e.order_id
GROUP BY e.region
ORDER BY product_cost_pct DESC;

-- What reduces list price to net price in each region?
SELECT
    e.region,
    ROUND(SUM(oi.gross_sales)     / SUM(oi.quantity), 2) AS list_price_per_unit,
    ROUND(SUM(oi.discount_amount) / SUM(oi.quantity), 2) AS discount_per_unit,
    ROUND(SUM(oi.tax_amount)      / SUM(oi.quantity), 2) AS tax_per_unit,
    ROUND(SUM(oi.shipping_cost)   / SUM(oi.quantity), 2) AS shipping_per_unit,
    ROUND(SUM(oi.net_sales)       / SUM(oi.quantity), 2) AS net_price_per_unit,
    ROUND(SUM(oi.discount_amount) / SUM(oi.gross_sales) * 100, 2) AS discount_pct_of_list
FROM order_items oi
JOIN ecommerce_sales_clean e ON oi.order_id = e.order_id
GROUP BY e.region
ORDER BY net_price_per_unit;

-- 1. Does net_sales = gross - discount + tax + shipping on every row?
SELECT COUNT(*) AS rows_checked,
       SUM(CASE WHEN ABS(net_sales - (gross_sales - discount_amount + tax_amount + shipping_cost)) > 0.05
                THEN 1 ELSE 0 END) AS mismatches
FROM ecommerce_sales_clean;

-- 2. Regional margin with tax removed
SELECT region,
       ROUND(SUM(net_sales - tax_amount), 2)  AS revenue_ex_tax,
       ROUND(SUM(profit - tax_amount), 2)     AS profit_ex_tax,
       ROUND(SUM(profit - tax_amount) / SUM(net_sales - tax_amount) * 100, 2) AS margin_ex_tax_pct,
       ROUND(SUM(profit) / SUM(net_sales) * 100, 2) AS reported_margin_pct,
       ROUND(SUM(tax_amount) / SUM(gross_sales - discount_amount) * 100, 2) AS tax_rate_pct
FROM ecommerce_sales_clean
GROUP BY region
ORDER BY margin_ex_tax_pct DESC;

-- 3. Company totals with tax removed
SELECT ROUND(SUM(tax_amount), 2)                 AS total_tax,
       ROUND(SUM(net_sales - tax_amount), 2)     AS revenue_ex_tax,
       ROUND(SUM(profit - tax_amount), 2)        AS profit_ex_tax,
       ROUND(SUM(profit - tax_amount) / SUM(net_sales - tax_amount) * 100, 2) AS margin_ex_tax_pct
FROM ecommerce_sales_clean;

-- 4. Category margin with tax removed (does the Electronics finding still hold?)
SELECT pc.product_category,
       ROUND(SUM(oi.profit - oi.tax_amount) / SUM(oi.net_sales - oi.tax_amount) * 100, 2) AS margin_ex_tax_pct,
       ROUND(SUM(oi.product_cost) / SUM(oi.net_sales - oi.tax_amount) * 100, 2)           AS product_cost_pct_ex_tax
FROM order_items oi
JOIN product_catalog pc ON oi.product_id = pc.product_id
GROUP BY pc.product_category
ORDER BY margin_ex_tax_pct DESC;

SELECT
    marketing_channel,
    COUNT(DISTINCT order_id)                     AS orders,
    ROUND(SUM(net_sales), 2)                     AS revenue,
    ROUND(SUM(profit), 2)                        AS profit,
    ROUND(SUM(profit) / SUM(net_sales) * 100, 2) AS profit_margin_pct,
    ROUND(SUM(profit - tax_amount) / SUM(net_sales - tax_amount) * 100, 2) AS margin_ex_tax_pct
FROM ecommerce_sales_clean
GROUP BY marketing_channel
ORDER BY margin_ex_tax_pct DESC;