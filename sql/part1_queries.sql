/* =============================================================================
   Peek — Product Analyst Data Challenge
   Part 1 — SQL (BigQuery Standard SQL)
   Dataset: bigquery-public-data.thelook_ecommerce
   Author:  Abraham Perez Martinez
   -----------------------------------------------------------------------------
   HOW TO RUN
   - Open in BigQuery console (or `bq query --use_legacy_sql=false`).
   - Each task below is a STANDALONE query. Run any block on its own.
   - Dates are parameterized via a `params` CTE at the top of each query —
     NO hard-coded cutoffs. Change values there to re-scope the analysis.

   SHARED CONVENTIONS (per challenge brief)
   - Completed sale : order_items.status = 'Complete' AND returned_at IS NULL
   - Revenue        : SUM(order_items.sale_price)
   - COGS           : SUM(inventory_items.cost) joined via inventory_item_id
   - Gross Profit   : Revenue - COGS
   - Month          : DATE_TRUNC(DATE(created_at), MONTH)
   - Activation     : a user's FIRST completed order (first purchase)

   DEFAULT ANALYSIS WINDOW
   - start_date    = 2019-01-01 (fixed lower bound; earliest order month currently 2019-02)
   - end_date_excl = DATE_TRUNC(CURRENT_DATE(), MONTH)
                     -> excludes the CURRENT partial month so trends/MoM are not
                        distorted by an incomplete month. (thelook is synthetic
                        and generates rows up to ~today.)
   ============================================================================= */


/* =============================================================================
   TASK A — MONTHLY FINANCIALS
   One row per month: revenue, completed orders, units, AOV, MoM revenue growth.
   - orders = COUNT(DISTINCT order_id) among completed line items
   - units  = COUNT(completed line items)
   - aov    = revenue / completed orders
   ============================================================================= */
WITH params AS (
  SELECT
    DATE '2019-01-01' AS start_date,
    DATE_TRUNC(CURRENT_DATE(), MONTH) AS end_date_excl
),

completed_items AS (
  SELECT
    oi.order_id,
    oi.sale_price,
    DATE_TRUNC(DATE(oi.created_at), MONTH) AS month
  FROM `bigquery-public-data.thelook_ecommerce.order_items` AS oi, params AS p
  WHERE
    oi.status = 'Complete'
    AND oi.returned_at IS NULL
    AND DATE(oi.created_at) >= p.start_date
    AND DATE(oi.created_at) < p.end_date_excl
),

monthly AS (
  SELECT
    month,
    SUM(sale_price) AS revenue,
    COUNT(DISTINCT order_id) AS orders,
    COUNT(*) AS units
  FROM completed_items
  GROUP BY month
)

SELECT
  month,
  orders,
  units,
  ROUND(revenue, 2) AS revenue,
  ROUND(SAFE_DIVIDE(revenue, orders), 2) AS aov,
  ROUND(SAFE_DIVIDE(
    revenue - LAG(revenue) OVER (ORDER BY month),
    LAG(revenue) OVER (ORDER BY month)
  ), 4) AS mom_revenue_growth
FROM monthly
ORDER BY month;


/* =============================================================================
   TASK B — NEW vs RETURNING MIX (per month)
   Definitions:
   - active_customers    : distinct users with >=1 completed order in the month
   - new_customers       : users whose FIRST-EVER completed order is in that month
   - returning_customers : active users whose first completed order was earlier
   - revenue_new / revenue_returning : month revenue split by that tag
   - pct_rev_returning   : revenue_returning / total month revenue
   Note: "first-ever" is measured within the observed window (from start_date).
   ============================================================================= */
WITH params AS (
  SELECT
    DATE '2019-01-01' AS start_date,
    DATE_TRUNC(CURRENT_DATE(), MONTH) AS end_date_excl
),

completed AS (
  SELECT
    oi.user_id,
    oi.sale_price,
    DATE_TRUNC(DATE(oi.created_at), MONTH) AS month
  FROM `bigquery-public-data.thelook_ecommerce.order_items` AS oi, params AS p
  WHERE
    oi.status = 'Complete'
    AND oi.returned_at IS NULL
    AND DATE(oi.created_at) >= p.start_date
    AND DATE(oi.created_at) < p.end_date_excl
),

first_month AS (
  SELECT
    user_id,
    MIN(month) AS first_month
  FROM completed
  GROUP BY user_id
),

tagged AS (
  SELECT
    c.user_id,
    c.month,
    c.sale_price,
    IF(c.month = f.first_month, 'new', 'returning') AS cust_type
  FROM completed AS c
  INNER JOIN first_month AS f ON c.user_id = f.user_id
)

SELECT
  month,
  COUNT(DISTINCT user_id) AS active_customers,
  COUNT(DISTINCT IF(cust_type = 'new', user_id, NULL)) AS new_customers,
  COUNT(DISTINCT IF(cust_type = 'returning', user_id, NULL)) AS returning_customers,
  ROUND(SUM(IF(cust_type = 'new', sale_price, 0)), 2) AS revenue_new,
  ROUND(SUM(IF(cust_type = 'returning', sale_price, 0)), 2) AS revenue_returning,
  ROUND(SAFE_DIVIDE(
    SUM(IF(cust_type = 'returning', sale_price, 0)),
    SUM(sale_price)
  ), 4) AS pct_rev_returning
FROM tagged
GROUP BY month
ORDER BY month;


/* =============================================================================
   TASK C — 90-DAY CHURN (customer-centric, per month)
   - active_customers        : distinct users with a completed order in month M
   - churned_customers_90d   : active in M with NO completed order in the 90 days
                               AFTER the last day of M  (window: (EOM, EOM+90d])
   - churn_rate_90d          : churned / active
   Only months with a FULLY-OBSERVED 90-day forward window are reported
   (EOM + 90d <= latest completed-order date).
   ============================================================================= */
WITH params AS (
  SELECT
    DATE '2019-01-01' AS start_date,
    DATE_TRUNC(CURRENT_DATE(), MONTH) AS end_date_excl
),

completed AS (
  SELECT
    oi.user_id,
    DATE(oi.created_at) AS order_date,
    DATE_TRUNC(DATE(oi.created_at), MONTH) AS month
  FROM `bigquery-public-data.thelook_ecommerce.order_items` AS oi, params AS p
  WHERE
    oi.status = 'Complete'
    AND oi.returned_at IS NULL
    AND DATE(oi.created_at) >= p.start_date
    AND DATE(oi.created_at) < p.end_date_excl
),

active AS (
  SELECT DISTINCT
    month,
    user_id
  FROM completed
),

bounds AS (
  SELECT MAX(order_date) AS max_dt FROM completed
),

flags AS (
-- retained = has any completed order in the 90 days after month-end
  SELECT
    a.month,
    a.user_id,
    MAX(IF(c.user_id IS NOT NULL, 1, 0)) AS retained
  FROM active AS a
  LEFT JOIN completed AS c
    ON
      a.user_id = c.user_id
      AND c.order_date > LAST_DAY(a.month)
      AND c.order_date <= DATE_ADD(LAST_DAY(a.month), INTERVAL 90 DAY)
  GROUP BY a.month, a.user_id
)

SELECT
  f.month,
  COUNT(*) AS active_customers,
  COUNTIF(f.retained = 0) AS churned_customers_90d,
  ROUND(SAFE_DIVIDE(COUNTIF(f.retained = 0), COUNT(*)), 4) AS churn_rate_90d
FROM flags AS f, bounds AS b
WHERE DATE_ADD(LAST_DAY(f.month), INTERVAL 90 DAY) <= b.max_dt
GROUP BY f.month
ORDER BY f.month;


/* =============================================================================
   TASK C — OPTIONAL STRETCH: COHORT RETENTION HEATMAP (long format)
   rows   = cohort_month (user's first completed-order month)
   columns= month_offset (whole months since first purchase, 0 = acquisition)
   value  = retention_rate = distinct active cohort users at offset / cohort size
   Pivot month_offset -> columns in the viz tool to render the heatmap.
   ============================================================================= */
WITH params AS (
  SELECT
    DATE '2019-01-01' AS start_date,
    DATE_TRUNC(CURRENT_DATE(), MONTH) AS end_date_excl
),

completed AS (
  SELECT
    oi.user_id,
    DATE_TRUNC(DATE(oi.created_at), MONTH) AS month
  FROM `bigquery-public-data.thelook_ecommerce.order_items` AS oi, params AS p
  WHERE
    oi.status = 'Complete'
    AND oi.returned_at IS NULL
    AND DATE(oi.created_at) >= p.start_date
    AND DATE(oi.created_at) < p.end_date_excl
),

first_month AS (
  SELECT
    user_id,
    MIN(month) AS cohort_month
  FROM completed
  GROUP BY user_id
),

activity AS (
  SELECT DISTINCT
    f.cohort_month,
    c.user_id,
    DATE_DIFF(c.month, f.cohort_month, MONTH) AS month_offset
  FROM completed AS c
  INNER JOIN first_month AS f ON c.user_id = f.user_id
),

cohort_size AS (
  SELECT
    cohort_month,
    COUNT(DISTINCT user_id) AS cohort_size
  FROM first_month
  GROUP BY cohort_month
)

SELECT
  a.cohort_month,
  a.month_offset,
  s.cohort_size,
  COUNT(DISTINCT a.user_id) AS active_users,
  ROUND(SAFE_DIVIDE(COUNT(DISTINCT a.user_id), s.cohort_size), 4) AS retention_rate
FROM activity AS a
INNER JOIN cohort_size AS s ON a.cohort_month = s.cohort_month
GROUP BY a.cohort_month, a.month_offset, s.cohort_size
ORDER BY a.cohort_month, a.month_offset;


/* =============================================================================
   TASK D — PRODUCT CHANGE IMPACT (SCENARIO)
   Hypothetical policy on 2022-01-15: "Free shipping for orders over $100".
   The feature is NOT in the data, so we build an IMPACT-ANALYSIS SCAFFOLD:
     * order-level revenue, COGS and gross profit
     * a pre/post period split around the policy date
     * a proxy treatment/control split: orders >= $100 (would get free shipping,
       "treatment") vs < $100 ("control")
   We emit three views (D1 trend, D2 pre/post x value-band, D3 segment).

   ASSUMPTIONS (see README for full list)
   - No shipping_fee field exists -> we cannot measure shipping cost directly,
     so we proxy "affected" orders by order value crossing the $100 threshold.
   - Pre/post is a naive before/after -- a clean read needs a control for the
     underlying growth trend (hence the >= $100 vs < $100 diff-in-diff frame).
   ============================================================================= */

-- Shared order-level base for Task D (re-declared per query to keep each standalone)
-- D1 — Monthly trend: revenue, orders, AOV, gross profit (overall)
WITH params AS (
  SELECT
    DATE '2019-01-01' AS start_date,
    DATE '2022-01-15' AS policy_date,
    100.0 AS free_ship_threshold,
    DATE_TRUNC(CURRENT_DATE(), MONTH) AS end_date_excl
),

order_level AS (
  SELECT
    oi.order_id,
    ANY_VALUE(oi.user_id) AS user_id,
    MIN(DATE(oi.created_at)) AS order_date,
    SUM(oi.sale_price) AS order_revenue,
    SUM(inv.cost) AS order_cogs
  FROM `bigquery-public-data.thelook_ecommerce.order_items` AS oi
  INNER JOIN params AS p ON TRUE
  LEFT JOIN `bigquery-public-data.thelook_ecommerce.inventory_items` AS inv
    ON oi.inventory_item_id = inv.id
  WHERE
    oi.status = 'Complete'
    AND oi.returned_at IS NULL
    AND DATE(oi.created_at) >= p.start_date
    AND DATE(oi.created_at) < p.end_date_excl
  GROUP BY oi.order_id
)

SELECT
  DATE_TRUNC(order_date, MONTH) AS month,
  COUNT(*) AS orders,
  ROUND(SUM(order_revenue), 2) AS revenue,
  ROUND(AVG(order_revenue), 2) AS aov,
  ROUND(SUM(order_revenue - order_cogs), 2) AS gross_profit,
  ROUND(SAFE_DIVIDE(
    SUM(order_revenue - order_cogs),
    SUM(order_revenue)
  ), 4) AS gross_margin
FROM order_level
GROUP BY month
ORDER BY month;


-- D2 — Pre/Post x value-band scaffold (difference-in-differences frame)
WITH params AS (
  SELECT
    DATE '2019-01-01' AS start_date,
    DATE '2022-01-15' AS policy_date,
    100.0 AS free_ship_threshold,
    DATE_TRUNC(CURRENT_DATE(), MONTH) AS end_date_excl
),

order_level AS (
  SELECT
    oi.order_id,
    MIN(DATE(oi.created_at)) AS order_date,
    SUM(oi.sale_price) AS order_revenue,
    SUM(inv.cost) AS order_cogs
  FROM `bigquery-public-data.thelook_ecommerce.order_items` AS oi
  INNER JOIN params AS p ON TRUE
  LEFT JOIN `bigquery-public-data.thelook_ecommerce.inventory_items` AS inv
    ON oi.inventory_item_id = inv.id
  WHERE
    oi.status = 'Complete'
    AND oi.returned_at IS NULL
    AND DATE(oi.created_at) >= p.start_date
    AND DATE(oi.created_at) < p.end_date_excl
  GROUP BY oi.order_id
),

enriched AS (
  SELECT
    o.order_revenue,
    (o.order_revenue - o.order_cogs) AS gross_profit,
    IF(
      o.order_revenue >= (SELECT params.free_ship_threshold FROM params),
      'gte_100', 'lt_100'
    ) AS value_band,
    IF(
      o.order_date >= (SELECT params.policy_date FROM params),
      'post', 'pre'
    ) AS period
  FROM order_level AS o
)

SELECT
  value_band,
  period,
  COUNT(*) AS orders,
  ROUND(SUM(order_revenue), 0) AS revenue,
  ROUND(AVG(order_revenue), 2) AS aov,
  ROUND(SUM(gross_profit), 0) AS gross_profit,
  ROUND(SAFE_DIVIDE(SUM(gross_profit), SUM(order_revenue)), 4) AS gross_margin
FROM enriched
GROUP BY value_band, period
ORDER BY value_band, period;


-- D3 — Segment view: pre/post AOV & revenue by traffic_source
WITH params AS (
  SELECT
    DATE '2019-01-01' AS start_date,
    DATE '2022-01-15' AS policy_date,
    DATE_TRUNC(CURRENT_DATE(), MONTH) AS end_date_excl
),

order_level AS (
  SELECT
    oi.order_id,
    ANY_VALUE(oi.user_id) AS user_id,
    MIN(DATE(oi.created_at)) AS order_date,
    SUM(oi.sale_price) AS order_revenue
  FROM `bigquery-public-data.thelook_ecommerce.order_items` AS oi
  INNER JOIN params AS p ON TRUE
  WHERE
    oi.status = 'Complete'
    AND oi.returned_at IS NULL
    AND DATE(oi.created_at) >= p.start_date
    AND DATE(oi.created_at) < p.end_date_excl
  GROUP BY oi.order_id
),

enriched AS (
  SELECT
    o.order_revenue,
    u.traffic_source,
    IF(o.order_date >= (SELECT params.policy_date FROM params), 'post', 'pre') AS period
  FROM order_level AS o
  LEFT JOIN `bigquery-public-data.thelook_ecommerce.users` AS u
    ON o.user_id = u.id
)

SELECT
  traffic_source,
  period,
  COUNT(*) AS orders,
  ROUND(SUM(order_revenue), 0) AS revenue,
  ROUND(AVG(order_revenue), 2) AS aov
FROM enriched
GROUP BY traffic_source, period
ORDER BY traffic_source, period;
