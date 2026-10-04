CREATE DATABASE olist_db;

CREATE TABLE orders (
  order_id                       TEXT PRIMARY KEY,
  customer_id                    TEXT,
  order_status                   TEXT,
  order_purchase_timestamp       TIMESTAMP,
  order_approved_at              TIMESTAMP,
  order_delivered_carrier_date   TIMESTAMP,
  order_delivered_customer_date  TIMESTAMP,
  order_estimated_delivery_date  TIMESTAMP
);

CREATE TABLE order_items (
  order_id             TEXT,
  order_item_id        INT,
  product_id           TEXT,
  seller_id            TEXT,
  shipping_limit_date  TIMESTAMP,
  price                NUMERIC(10,2),
  freight_value        NUMERIC(10,2)
);


CREATE TABLE customers (
  customer_id               TEXT PRIMARY KEY,
  customer_unique_id        TEXT,
  customer_zip_code_prefix  TEXT,
  customer_city             TEXT,
  customer_state            TEXT
);

CREATE TABLE order_reviews (
  review_id                 TEXT,
  order_id                  TEXT,
  review_score              INT,
  review_comment_title      TEXT,
  review_comment_message    TEXT,
  review_creation_date      TIMESTAMP,
  review_answer_timestamp   TIMESTAMP
);

DROP TABLE IF EXISTS order_fact;


CREATE TABLE order_fact AS
WITH items AS (
  SELECT order_id,
         COUNT(*)                  AS n_items,
         COUNT(DISTINCT seller_id) AS n_sellers,
         MIN(seller_id)            AS any_seller_id,
         MAX(shipping_limit_date)  AS shipping_limit_ts,
         SUM(price)                AS item_revenue,
         SUM(freight_value)        AS freight_value
  FROM order_items
  GROUP BY order_id
),
rev AS (
  SELECT order_id, review_score, review_creation_date,
         ROW_NUMBER() OVER (
           PARTITION BY order_id
           ORDER BY review_creation_date DESC, review_answer_timestamp DESC
         ) AS rn
  FROM order_reviews
)
SELECT o.order_id,
       c.customer_unique_id,
       c.customer_state,
       o.order_purchase_timestamp      AS purchase_ts,
       o.order_approved_at             AS approved_ts,
       o.order_delivered_carrier_date  AS carrier_ts,
       o.order_delivered_customer_date AS delivered_ts,
       o.order_estimated_delivery_date AS estimated_ts,
       i.n_items,
       i.n_sellers,
       CASE WHEN i.n_sellers = 1 THEN i.any_seller_id END AS seller_id,
       i.shipping_limit_ts,
       i.item_revenue,
       i.freight_value,
       i.item_revenue + i.freight_value AS gmv,
       r.review_score,
       r.review_creation_date
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
JOIN items i     ON i.order_id = o.order_id
LEFT JOIN rev r  ON r.order_id = o.order_id AND r.rn = 1
WHERE o.order_status = 'delivered'
  AND o.order_approved_at IS NOT NULL
  AND o.order_delivered_carrier_date IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL;


-- Simple Analysis--

-- Total rows in fact table
SELECT COUNT(*) AS total_orders
FROM order_fact;

-- Compare with delivered orders in raw table
SELECT
  (SELECT COUNT(*) FROM order_fact) AS fact_orders,
  (SELECT COUNT(*) FROM orders WHERE order_status = 'delivered') AS delivered_orders;

-- On-time vs Late orders
SELECT
  CASE 
    WHEN delivered_ts::date <= estimated_ts::date THEN 'On-time'
    ELSE 'Late'
  END AS delivery_status,
  COUNT(*) AS orders
FROM order_fact
GROUP BY 1;

-- Total GMV
SELECT
  ROUND(SUM(gmv), 2) AS total_revenue,
  ROUND(AVG(gmv), 2) AS avg_order_value
FROM order_fact;

-- Average rating
SELECT
  ROUND(AVG(review_score), 2) AS avg_review_score
FROM order_fact;

-- Late orders have worse ratings?
SELECT
  CASE 
    WHEN delivered_ts::date <= estimated_ts::date THEN 'On-time'
    ELSE 'Late'
  END AS delivery_status,
  ROUND(AVG(review_score), 2) AS avg_rating
FROM order_fact
GROUP BY 1;


