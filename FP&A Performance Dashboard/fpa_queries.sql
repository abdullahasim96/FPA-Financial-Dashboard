-- ============================================================
-- FP&A Variance Analysis – SQL Query Pack
-- Source table : fpa_data
-- Columns      : Department (text), Month (text 'Mon-YYYY'),
--                Budget (numeric), Actual (numeric),
--                Variance (numeric), Variance_pct (numeric)
-- Dialect      : PostgreSQL  (see notes for SQL Server / MySQL / BigQuery)
-- ============================================================

-- Reusable helper: convert "Jan-2024" -> real DATE for ordering & windowing
-- PostgreSQL  : TO_DATE(Month, 'Mon-YYYY')
-- SQL Server  : TRY_CONVERT(date, '01-' + Month, 106)
-- MySQL       : STR_TO_DATE(CONCAT('01-', Month), '%d-%b-%Y')
-- BigQuery    : PARSE_DATE('%b-%Y', Month)


-- ============================================================
-- 1) Budget vs Actual Variance by Month  (company-wide)
-- ============================================================
WITH base AS (
    SELECT
        TO_DATE(Month, 'Mon-YYYY') AS month_date,
        Month                       AS month_label,
        Budget,
        Actual
    FROM fpa_data
)
SELECT
    month_label,
    SUM(Budget)                                   AS total_budget,
    SUM(Actual)                                   AS total_actual,
    SUM(Actual) - SUM(Budget)                     AS variance,
    ROUND( (SUM(Actual) - SUM(Budget))
           * 100.0 / NULLIF(SUM(Budget), 0), 2)   AS variance_pct
FROM base
GROUP BY month_label, month_date
ORDER BY month_date;


-- ============================================================
-- 2) Month-over-Month Revenue Change %
--    Assumption: Revenue = Actual where Department = 'Sales'
-- ============================================================
WITH revenue AS (
    SELECT
        TO_DATE(Month, 'Mon-YYYY') AS month_date,
        Month                       AS month_label,
        Actual                      AS revenue
    FROM fpa_data
    WHERE Department = 'Sales'
)
SELECT
    month_label,
    revenue,
    LAG(revenue) OVER (ORDER BY month_date)                          AS prior_month_revenue,
    revenue - LAG(revenue) OVER (ORDER BY month_date)                AS mom_change,
    ROUND(
        ( revenue - LAG(revenue) OVER (ORDER BY month_date) )
        * 100.0 / NULLIF(LAG(revenue) OVER (ORDER BY month_date), 0)
    , 2)                                                             AS mom_change_pct
FROM revenue
ORDER BY month_date;


-- ============================================================
-- 3) Top 5 Cost Categories by Spend (YTD)
--    Assumption: "Cost categories" = non-Sales departments
-- ============================================================
SELECT
    Department          AS cost_category,
    SUM(Actual)         AS total_spend,
    SUM(Budget)         AS total_budget,
    SUM(Actual) - SUM(Budget) AS variance_vs_budget,
    ROUND( (SUM(Actual) - SUM(Budget))
           * 100.0 / NULLIF(SUM(Budget), 0), 2)   AS variance_pct
FROM fpa_data
WHERE Department <> 'Sales'
GROUP BY Department
ORDER BY total_spend DESC
LIMIT 5;
-- SQL Server: replace LIMIT 5  with  TOP 5 in the SELECT


-- ============================================================
-- 4) Rolling 3-Month Average Revenue
--    Assumption: Revenue = Actual where Department = 'Sales'
-- ============================================================
WITH revenue AS (
    SELECT
        TO_DATE(Month, 'Mon-YYYY') AS month_date,
        Month                       AS month_label,
        Actual                      AS revenue
    FROM fpa_data
    WHERE Department = 'Sales'
)
SELECT
    month_label,
    revenue,
    ROUND(
        AVG(revenue) OVER (
            ORDER BY month_date
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        )
    , 2) AS rolling_3mo_avg_revenue
FROM revenue
ORDER BY month_date;


-- ============================================================
-- 5) Year-to-Date Profit Margin
--    Profit  = Sales revenue (Actual) − total non-Sales spend (Actual)
--    Margin  = Profit / Revenue
-- ============================================================
WITH monthly_pl AS (
    SELECT
        TO_DATE(Month, 'Mon-YYYY')                                    AS month_date,
        Month                                                          AS month_label,
        SUM(CASE WHEN Department  = 'Sales' THEN Actual ELSE 0 END)   AS revenue,
        SUM(CASE WHEN Department <> 'Sales' THEN Actual ELSE 0 END)   AS costs
    FROM fpa_data
    GROUP BY Month
),
ytd AS (
    SELECT
        month_label,
        month_date,
        SUM(revenue) OVER (ORDER BY month_date) AS ytd_revenue,
        SUM(costs)   OVER (ORDER BY month_date) AS ytd_costs
    FROM monthly_pl
)
SELECT
    month_label,
    ytd_revenue,
    ytd_costs,
    ytd_revenue - ytd_costs                                      AS ytd_profit,
    ROUND( (ytd_revenue - ytd_costs)
           * 100.0 / NULLIF(ytd_revenue, 0), 2)                  AS ytd_profit_margin_pct
FROM ytd
ORDER BY month_date;
