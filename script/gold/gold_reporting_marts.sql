-- ============================================================================
-- LAYER: GOLD (SEMANTIC REPORTING VIEW LAYER)
-- PURPOSE: High-Performance Analytical Aggregations Serving Power BI DirectQuery
-- ============================================================================

USE IPL_Analytics_DW;
GO

-- ============================================================================
-- VIEW: gold.mart_batsman_performance
-- DESCRIPTION: Career batting strike rate, runs volume, and boundary calculation
-- ============================================================================
IF OBJECT_ID('gold.mart_batsman_performance', 'V') IS NOT NULL
    DROP VIEW gold.mart_batsman_performance;
GO

CREATE VIEW gold.mart_batsman_performance AS
SELECT 
    p.player_id,
    p.player_fullname AS batsman_name,
    COUNT(d.delivery_id) AS balls_faced,
    SUM(d.batsman_runs) AS total_runs,
    ROUND((CAST(SUM(d.batsman_runs) AS FLOAT) / COUNT(d.delivery_id)) * 100, 2) AS strike_rate,
    SUM(CASE WHEN d.batsman_runs = 4 THEN 1 ELSE 0 END) AS total_fours,
    SUM(CASE WHEN d.batsman_runs = 6 THEN 1 ELSE 0 END) AS total_sixes
FROM silver.fact_deliveries d
JOIN silver.dim_players p ON d.batter_id = p.player_id
GROUP BY p.player_id, p.player_fullname;
GO

-- ============================================================================
-- VIEW: gold.mart_bowler_performance
-- DESCRIPTION: Economy rate and aggregate wicket tracking metrics
-- ============================================================================
IF OBJECT_ID('gold.mart_bowler_performance', 'V') IS NOT NULL
    DROP VIEW gold.mart_bowler_performance;
GO

CREATE VIEW gold.mart_bowler_performance AS
SELECT 
    p.player_id,
    p.player_fullname AS bowler_name,
    COUNT(d.delivery_id) AS balls_bowled,
    ROUND(CAST(COUNT(d.delivery_id) AS FLOAT) / 6, 1) AS overs_bowled,
    SUM(d.total_runs) - SUM(d.extra_runs) AS runs_conceded, 
    SUM(d.is_wicket) AS total_wickets,
    ROUND((CAST(SUM(d.total_runs) - SUM(d.extra_runs) AS FLOAT) / (CAST(COUNT(d.delivery_id) AS FLOAT) / 6)), 2) AS economy_rate
FROM silver.fact_deliveries d
JOIN silver.dim_players p ON d.bowler_id = p.player_id
GROUP BY p.player_id, p.player_fullname
-- Defensive engineering filter: Removes accidental or part-time records
HAVING COUNT(d.delivery_id) >= 6; 
GO

-- ============================================================================
-- VIEW: gold.mart_team_standings
-- DESCRIPTION: Historical, year-wise dynamic team standings scoreboard
-- ============================================================================
IF OBJECT_ID('gold.mart_team_standings', 'V') IS NOT NULL
    DROP VIEW gold.mart_team_standings;
GO

CREATE VIEW gold.mart_team_standings AS
WITH MatchBase AS (
    -- Step 1: Isolate historical calendars and win/toss statuses per franchise boundaries
    SELECT 
        t.team_id,
        t.team_name,
        YEAR(m.match_date) AS match_year,
        m.match_id,
        CASE WHEN m.winner_id = t.team_id THEN 1 ELSE 0 END AS is_win,
        CASE WHEN m.toss_winner_id = t.team_id THEN 1 ELSE 0 END AS is_toss_win
    FROM silver.dim_teams t
    INNER JOIN silver.fact_matches m ON t.team_id = m.team1_id OR t.team_id = m.team2_id
),

YearlyMatchAggregates AS (
    -- Step 2: Consolidate total matches, win configurations, and coin toss advantages per season
    SELECT 
        team_id,
        team_name,
        match_year,
        COUNT(match_id) AS total_matches_played,
        SUM(is_win) AS total_wins,
        SUM(is_toss_win) AS toss_wins
    FROM MatchBase
    GROUP BY team_id, team_name, match_year
),

YearlyRunAggregates AS (
    -- Step 3: Compute gross runs scored out of granular ball-by-ball fact contexts
    SELECT 
        d.batting_team_id AS team_id,
        YEAR(m.match_date) AS match_year,
        SUM(d.total_runs) AS total_runs_this_year
    FROM silver.fact_deliveries d
    JOIN silver.fact_matches m ON d.match_id = m.match_id
    GROUP BY d.batting_team_id, YEAR(m.match_date)
)

-- Step 4: Map historical attributes cleanly into a final year-over-year standings array
SELECT 
    magg.team_name,
    magg.match_year,
    magg.total_matches_played,
    magg.total_wins,
    magg.toss_wins,
    ISNULL(ragg.total_runs_this_year, 0) AS total_runs_this_year
FROM YearlyMatchAggregates magg
LEFT JOIN YearlyRunAggregates ragg ON magg.team_id = ragg.team_id AND magg.match_year = ragg.match_year;
GO