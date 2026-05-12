{{
    config(
        materialized='view',
        schema='staging',
        tags=['staging', 'orders']
    )
}}

/*
stg_orders.sql — Staging model for raw orders

Responsibilities:
  1. Rename columns to consistent snake_case naming
  2. Cast data types (string → date, string → decimal)
  3. Filter out invalid/test records
  4. Standardize categorical values (status, region)
  5. Add basic derived columns (total_amount)

Source: raw.orders (loaded via COPY INTO from ADLS Parquet)
*/

WITH source AS (

    SELECT * FROM {{ source('raw', 'orders') }}

),

renamed AS (

    SELECT
        -- Primary key
        CAST(order_id AS VARCHAR(50))       AS order_id,

        -- Foreign keys
        CAST(customer_id AS VARCHAR(50))    AS customer_id,

        -- Dimensions
        CAST(product AS VARCHAR(200))       AS product_name,
        LOWER(TRIM(CAST(status AS VARCHAR(50))))   AS status,
        LOWER(TRIM(CAST(region AS VARCHAR(100))))  AS region,

        -- Measures
        CAST(amount AS DECIMAL(10, 2))      AS unit_price,
        CAST(quantity AS INT)               AS quantity,
        CAST(amount AS DECIMAL(10, 2))
            * CAST(quantity AS INT)         AS total_amount,

        -- Dates
        CAST(order_date AS DATE)            AS order_date,
        YEAR(CAST(order_date AS DATE))      AS order_year,
        MONTH(CAST(order_date AS DATE))     AS order_month,
        DAY(CAST(order_date AS DATE))       AS order_day,

        -- Metadata
        GETDATE()                           AS _loaded_at

    FROM source

),

cleaned AS (

    SELECT *
    FROM renamed
    WHERE
        -- Remove rows with null primary keys
        order_id IS NOT NULL
        AND customer_id IS NOT NULL

        -- Remove rows with invalid amounts
        AND unit_price > 0
        AND quantity > 0
        AND total_amount > 0

        -- Remove rows with invalid dates
        AND order_date IS NOT NULL
        AND order_date >= '2020-01-01'
        AND order_date <= GETDATE()

        -- Remove test/dummy records
        AND order_id NOT LIKE 'TEST%'
        AND customer_id NOT LIKE 'TEST%'

        -- Standardize status values
        AND status IN ('pending', 'processing', 'completed', 'cancelled', 'refunded', 'unknown')

)

SELECT * FROM cleaned
