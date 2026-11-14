-- ============================================================================
-- RETAILFLOW | RETAIL ORDER FULFILLMENT OPTIMIZATION
-- Author: Huy Tran
-- Database: PostgreSQL
-- Source: Simulated retail pickup orders (RetailFlow sample dataset)
-- Expected table: retail_orders
--
-- PURPOSE
-- Explore pickup wait times, order picking duration, late pickup statuses,
-- shift performance, and operational bottlenecks.
--
-- HOW TO USE
-- 1. Connect to the database containing retail_orders in pgAdmin.
-- 2. Load the supplied sample CSV if the table is not already populated.
-- 3. Run each numbered SELECT statement separately, or execute the whole file.
-- 4. Compare results with the README and update documented metrics if needed.
--
-- KNOWN COLUMNS
-- order_id, order_date, employee_shift, number_of_items,
-- picking_minutes, wait_minutes, pickup_status
--
-- IMPORTANT
-- This is synthetic portfolio data, not production operational data.
-- 'Late' is the provided pickup_status label, not a status inferred from
-- wait_minutes. Wait > 10 minutes is a separate investigative threshold.
-- These descriptive queries do not establish causation or prove savings.
-- ============================================================================

-- 01 | Inspect source records and column definitions
SELECT *
FROM retail_orders
LIMIT 10;

-- 02 | Verify row count, unique identifiers, missing fields, and invalid values
SELECT
    COUNT(*) AS total_orders,
    COUNT(DISTINCT order_id) AS unique_order_ids,
    COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_or_null_id_rows,
    COUNT(*) FILTER (
        WHERE order_id IS NULL OR order_date IS NULL
           OR employee_shift IS NULL OR number_of_items IS NULL
           OR picking_minutes IS NULL OR wait_minutes IS NULL
           OR pickup_status IS NULL
    ) AS incomplete_rows,
    COUNT(*) FILTER (
        WHERE number_of_items < 0 OR picking_minutes < 0 OR wait_minutes < 0
    ) AS negative_values
FROM retail_orders;

-- 03 | Identify any repeated non-null order IDs
SELECT order_id, COUNT(*) AS occurrences
FROM retail_orders
WHERE order_id IS NOT NULL
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY occurrences DESC, order_id;

-- 04 | Overall operational KPI baseline
SELECT
    COUNT(*) AS total_orders,
    ROUND(AVG(wait_minutes), 2) AS avg_wait_minutes,
    ROUND(AVG(picking_minutes), 2) AS avg_picking_minutes,
    ROUND(AVG(number_of_items), 2) AS avg_items_per_order,
    MIN(wait_minutes) AS min_wait_minutes,
    MAX(wait_minutes) AS max_wait_minutes,
    COUNT(*) FILTER (WHERE pickup_status = 'Late') AS late_orders,
    ROUND(100.0 * COUNT(*) FILTER (WHERE pickup_status = 'Late')
          / NULLIF(COUNT(*), 0), 2) AS late_pct,
    COUNT(*) FILTER (WHERE wait_minutes > 10) AS waits_over_10_min,
    ROUND(100.0 * COUNT(*) FILTER (WHERE wait_minutes > 10)
          / NULLIF(COUNT(*), 0), 2) AS waits_over_10_pct
FROM retail_orders;

-- 05 | Shift-level comparison: volume, wait, picking, and late statuses
SELECT
    employee_shift,
    COUNT(*) AS total_orders,
    ROUND(AVG(wait_minutes), 2) AS avg_wait_minutes,
    ROUND(AVG(picking_minutes), 2) AS avg_picking_minutes,
    COUNT(*) FILTER (WHERE pickup_status = 'Late') AS late_orders,
    ROUND(100.0 * COUNT(*) FILTER (WHERE pickup_status = 'Late')
          / NULLIF(COUNT(*), 0), 2) AS late_pct
FROM retail_orders
GROUP BY employee_shift
ORDER BY avg_wait_minutes DESC;

-- 06 | Compare long-wait rates across shifts (separate from Late status)
SELECT
    employee_shift,
    COUNT(*) AS total_orders,
    COUNT(*) FILTER (WHERE wait_minutes > 10) AS waits_over_10_min,
    ROUND(100.0 * COUNT(*) FILTER (WHERE wait_minutes > 10)
          / NULLIF(COUNT(*), 0), 2) AS waits_over_10_pct,
    ROUND(AVG(wait_minutes), 2) AS avg_wait_minutes
FROM retail_orders
GROUP BY employee_shift
ORDER BY waits_over_10_pct DESC;
-- 07 | Monthly trend in volume, waiting, and Late status
SELECT
    DATE_TRUNC('month', order_date)::date AS month,
    COUNT(*) AS total_orders,
    ROUND(AVG(wait_minutes), 2) AS avg_wait_minutes,
    ROUND(AVG(picking_minutes), 2) AS avg_picking_minutes,
    COUNT(*) FILTER (WHERE pickup_status = 'Late') AS late_orders,
    ROUND(100.0 * COUNT(*) FILTER (WHERE pickup_status = 'Late')
          / NULLIF(COUNT(*), 0), 2) AS late_pct
FROM retail_orders
GROUP BY DATE_TRUNC('month', order_date)::date
ORDER BY month;

-- 08 | Order complexity: item-count bands
WITH banded_orders AS (
    SELECT
        CASE
            WHEN number_of_items IS NULL THEN 'Unknown'
            WHEN number_of_items <= 10 THEN '01-10'
            WHEN number_of_items <= 25 THEN '11-25'
            WHEN number_of_items <= 40 THEN '26-40'
            ELSE '41+'
        END AS item_band,
        picking_minutes, wait_minutes, pickup_status
    FROM retail_orders
)
SELECT
    item_band,
    COUNT(*) AS total_orders,
    ROUND(AVG(picking_minutes), 2) AS avg_picking_minutes,
    ROUND(AVG(wait_minutes), 2) AS avg_wait_minutes,
    ROUND(100.0 * COUNT(*) FILTER (WHERE pickup_status = 'Late')
          / NULLIF(COUNT(*), 0), 2) AS late_pct
FROM banded_orders
GROUP BY item_band
ORDER BY item_band;
-- 09 | Shift and item complexity together: compare order mix
WITH banded_orders AS (
    SELECT
        employee_shift,
        CASE
            WHEN number_of_items IS NULL THEN 'Unknown'
            WHEN number_of_items <= 10 THEN '01-10'
            WHEN number_of_items <= 25 THEN '11-25'
            WHEN number_of_items <= 40 THEN '26-40'
            ELSE '41+'
        END AS item_band,
        picking_minutes, wait_minutes
    FROM retail_orders
)
SELECT
    employee_shift, item_band,
    COUNT(*) AS total_orders,
    ROUND(AVG(picking_minutes), 2) AS avg_picking_minutes,
    ROUND(AVG(wait_minutes), 2) AS avg_wait_minutes
FROM banded_orders
GROUP BY employee_shift, item_band
ORDER BY employee_shift, item_band;
-- 10 | Longest-waiting orders: exceptions worth investigating
SELECT
    order_id, order_date, employee_shift, number_of_items,
    picking_minutes, wait_minutes, pickup_status
FROM retail_orders
WHERE wait_minutes IS NOT NULL
ORDER BY wait_minutes DESC, order_id
LIMIT 20;

-- 11 | Compare recorded Late vs On Time status and actual waits
SELECT
    pickup_status,
    COUNT(*) AS total_orders,
    ROUND(AVG(wait_minutes), 2) AS avg_wait_minutes,
    ROUND(AVG(picking_minutes), 2) AS avg_picking_minutes,
    COUNT(*) FILTER (WHERE wait_minutes > 10) AS waits_over_10_min
FROM retail_orders
GROUP BY pickup_status
ORDER BY pickup_status;

-- 12 | Cross-tab: status label versus 10-minute wait threshold
SELECT
    pickup_status,
    CASE
        WHEN wait_minutes IS NULL THEN 'Unknown wait'
        WHEN wait_minutes > 10 THEN 'Over 10 minutes'
        ELSE '10 minutes or less'
    END AS wait_category,
    COUNT(*) AS total_orders
FROM retail_orders
GROUP BY pickup_status, wait_category
ORDER BY pickup_status, wait_category;
-- 13 | Rank shifts by average wait using a window function
WITH shift_metrics AS (
    SELECT
        employee_shift,
        COUNT(*) AS total_orders,
        ROUND(AVG(wait_minutes), 2) AS avg_wait_minutes
    FROM retail_orders
    GROUP BY employee_shift
)
SELECT
    DENSE_RANK() OVER (ORDER BY avg_wait_minutes DESC NULLS LAST) AS wait_rank,
    employee_shift, total_orders, avg_wait_minutes
FROM shift_metrics
ORDER BY wait_rank, employee_shift;

-- 14 | Compare each shift's order share with its share of Late orders
WITH shift_counts AS (
    SELECT
        employee_shift,
        COUNT(*) AS total_orders,
        COUNT(*) FILTER (WHERE pickup_status = 'Late') AS late_orders
    FROM retail_orders
    GROUP BY employee_shift
)
SELECT
    employee_shift, total_orders, late_orders,
    ROUND(100.0 * total_orders
          / NULLIF(SUM(total_orders) OVER (), 0), 2) AS order_share_pct,
    ROUND(100.0 * late_orders
          / NULLIF(SUM(late_orders) OVER (), 0), 2) AS late_order_share_pct
FROM shift_counts
ORDER BY late_orders DESC;

-- 15 | Correlation: item count and picking duration
-- Correlation is descriptive and does not demonstrate causation.
SELECT
    COUNT(*) FILTER (
        WHERE number_of_items IS NOT NULL AND picking_minutes IS NOT NULL
    ) AS paired_observations,
    ROUND(CORR(number_of_items::double precision,
               picking_minutes::double precision)::numeric, 3)
        AS items_vs_picking_correlation
FROM retail_orders;
-- 16 | Correlation: picking duration and customer wait
SELECT
    COUNT(*) FILTER (
        WHERE picking_minutes IS NOT NULL AND wait_minutes IS NOT NULL
    ) AS paired_observations,
    ROUND(CORR(picking_minutes::double precision,
               wait_minutes::double precision)::numeric, 3)
        AS picking_vs_wait_correlation
FROM retail_orders;

-- 17 | Wait distribution by shift: median and 90th percentile
SELECT
    employee_shift,
    COUNT(*) AS total_orders,
    ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP
          (ORDER BY wait_minutes))::numeric, 2) AS median_wait_minutes,
    ROUND((PERCENTILE_CONT(0.9) WITHIN GROUP
          (ORDER BY wait_minutes))::numeric, 2) AS p90_wait_minutes
FROM retail_orders
GROUP BY employee_shift
ORDER BY p90_wait_minutes DESC;

-- 18 | Final shift scorecard for dashboard/reporting
SELECT
    employee_shift,
    COUNT(*) AS total_orders,
    ROUND(AVG(number_of_items), 2) AS avg_items,
    ROUND(AVG(picking_minutes), 2) AS avg_picking_minutes,
    ROUND(AVG(wait_minutes), 2) AS avg_wait_minutes,
    COUNT(*) FILTER (WHERE pickup_status = 'Late') AS late_orders,
    ROUND(100.0 * COUNT(*) FILTER (WHERE pickup_status = 'Late')
          / NULLIF(COUNT(*), 0), 2) AS late_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE wait_minutes > 10)
          / NULLIF(COUNT(*), 0), 2) AS waits_over_10_pct
FROM retail_orders
GROUP BY employee_shift
ORDER BY employee_shift;

-- ============================================================================
-- ANALYST INTERPRETATION GUIDE
-- Compare absolute Late counts with Late percentages: high-volume shifts
-- may have more Late orders even if their Late percentage is lower.
-- Investigate shift staffing, order mix, and staging as hypotheses only.
-- Validate all outputs against the imported dataset before publishing metrics.
-- Suggested next step: visualize sections 04, 05, 07, 08, and 18.
-- ============================================================================
