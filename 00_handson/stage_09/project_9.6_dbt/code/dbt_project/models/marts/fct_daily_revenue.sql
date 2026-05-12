{{
    config(
        materialized='table',
        schema='marts',
        tags=['marts', 'revenue', 'production'],
        dist='hash',
        sort='order_date'
    )
}}

/*
fct_daily_revenue.sql — Daily Revenue Fact Table

Aggregates completed orders by date and product.
Used by Power BI dashboards and executive reporting.

Grain: one row per (order_date, product_name)

Upstream: stg_orders (via intermediate if enrichment needed)
*/

WITH orders AS (

    SELECT * FROM {{ ref('stg_orders') }}

),

completed_orders AS (

    SELECT *
    FROM orders
    WHERE status = 'completed'

),

daily_aggregates AS (

    SELECT
        -- Grain
        order_date,
        product_name,
        order_year,
        order_month,

        -- Revenue metrics
        SUM(total_amount)                   AS daily_revenue,
        SUM(unit_price * quantity)          AS gross_revenue,
        COUNT(*)                            AS order_count,
        SUM(quantity)                       AS units_sold,

        -- Order value metrics
        AVG(CAST(total_amount AS FLOAT))    AS avg_order_value,
        MIN(total_amount)                   AS min_order_value,
        MAX(total_amount)                   AS max_order_value,

        -- Customer metrics
        COUNT(DISTINCT customer_id)         AS unique_customers,

        -- Regional breakdown
        COUNT(CASE WHEN region = 'us-east'      THEN 1 END) AS orders_us_east,
        COUNT(CASE WHEN region = 'us-west'      THEN 1 END) AS orders_us_west,
        COUNT(CASE WHEN region = 'eu-west'      THEN 1 END) AS orders_eu_west,
        COUNT(CASE WHEN region = 'ap-southeast' THEN 1 END) AS orders_ap_southeast,

        -- Metadata
        GETDATE()                           AS _dbt_updated_at

    FROM completed_orders
    GROUP BY
        order_date,
        product_name,
        order_year,
        order_month

),

with_running_totals AS (

    SELECT
        *,

        -- Running total revenue (cumulative by product)
        SUM(daily_revenue) OVER (
            PARTITION BY product_name
            ORDER BY order_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_revenue,

        -- 7-day rolling average revenue
        AVG(CAST(daily_revenue AS FLOAT)) OVER (
            PARTITION BY product_name
            ORDER BY order_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) AS rolling_7d_avg_revenue,

        -- Revenue rank by day
        RANK() OVER (
            PARTITION BY order_date
            ORDER BY daily_revenue DESC
        ) AS revenue_rank_on_date

    FROM daily_aggregates

)

SELECT * FROM with_running_totals
ORDER BY order_date, product_name
