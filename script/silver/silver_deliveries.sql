-- ============================================================================
-- LAYER: SILVER DELIVERIES (BALL RECONCILIATION & GRAIN ALIGNMENT)
-- PURPOSE: Clean Ball Logs and map them to the Granular Deliveries Fact Table
-- ============================================================================

USE IPL_Analytics_DW;
GO

-- 1. Create intermediate structure for ball log processing
IF OBJECT_ID('silver.deliveries_clean', 'U') IS NOT NULL
    DROP TABLE silver.deliveries_clean;
GO

CREATE TABLE silver.deliveries_clean (
    match_id INT,
    inning INT,
    batting_team VARCHAR(100),
    bowling_team VARCHAR(100),
    over_no INT,                        
    ball INT,
    batter VARCHAR(100),
    bowler VARCHAR(100),
    non_striker VARCHAR(100),
    batsman_runs INT,
    extra_runs INT,
    total_runs INT,
    extras_type VARCHAR(50),
    is_wicket INT,                     
    player_dismissed VARCHAR(100),     
    dismissal_kind VARCHAR(50),
    fielder VARCHAR(100)               
);
GO

-- 2. Transform and cast raw staging rows to clean records
TRUNCATE TABLE silver.deliveries_clean;

INSERT INTO silver.deliveries_clean (
    match_id, inning, batting_team, bowling_team, over_no, ball, 
    batter, bowler, non_striker, batsman_runs, extra_runs, total_runs, 
    extras_type, is_wicket, player_dismissed, dismissal_kind, fielder
)
SELECT 
    TRY_CAST(match_id AS INT),
    TRY_CAST(inning AS INT),
    TRIM(batting_team),
    TRIM(bowling_team),
    TRY_CAST(over_no AS INT),
    TRY_CAST(ball AS INT),
    TRIM(batter),
    TRIM(bowler),
    TRIM(non_striker),
    TRY_CAST(batsman_runs AS INT),
    TRY_CAST(extra_runs AS INT),
    TRY_CAST(total_runs AS INT),
    CASE WHEN extras_type IS NULL OR TRIM(extras_type) = 'NA' THEN 'NA' ELSE TRIM(extras_type) END,
    CASE WHEN LOWER(TRIM(is_wicket)) IN ('1', 'true', 'yes') THEN 1 ELSE 0 END,
    TRIM(player_dismissed),
    TRIM(dismissal_kind),
    TRIM(fielder)
FROM bronze.deliveries;
GO

-- 3. Run the automated synchronization harness to capture newly uncovered player entries
INSERT INTO silver.dim_players (player_name, player_fullname)
SELECT DISTINCT UniqueStream, UniqueStream
FROM (
    SELECT batter AS UniqueStream FROM silver.deliveries_clean WHERE batter IS NOT NULL
    UNION
    SELECT bowler FROM silver.deliveries_clean WHERE bowler IS NOT NULL
    UNION
    SELECT non_striker FROM silver.deliveries_clean WHERE non_striker IS NOT NULL
    UNION
    SELECT player_dismissed FROM silver.deliveries_clean WHERE player_dismissed IS NOT NULL
    UNION
    SELECT fielder FROM silver.deliveries_clean WHERE fielder IS NOT NULL
) PlayerStream
WHERE UniqueStream NOT IN (SELECT player_name FROM silver.dim_players) AND UniqueStream <> 'NA';
GO

-- ============================================================================
-- TABLE: silver.fact_deliveries
-- DESCRIPTION: Highly granular ball-by-ball performance logging matrix
-- ============================================================================
IF OBJECT_ID('silver.fact_deliveries', 'U') IS NOT NULL
    DROP TABLE silver.fact_deliveries;
GO

CREATE TABLE silver.fact_deliveries (
    delivery_id INT IDENTITY(1,1) PRIMARY KEY, 
    match_id INT,                              
    inning INT,
    batting_team_id INT,                       
    bowling_team_id INT,                       
    [over_no] INT,                             
    ball INT,
    batter_id INT,                             
    bowler_id INT,                             
    non_striker_id INT,                        
    batsman_runs INT,
    extra_runs INT,
    total_runs INT,
    extras_type VARCHAR(50),
    is_wicket INT,                             
    player_dismissed_id INT,                   
    dismissal_kind VARCHAR(50),
    fielder_id INT                             
);
GO

-- 4. Load clean data entries into the final fact tables using surrogate keys
TRUNCATE TABLE silver.fact_deliveries;

INSERT INTO silver.fact_deliveries (
    match_id, inning, batting_team_id, bowling_team_id, [over_no], ball,
    batter_id, bowler_id, non_striker_id, batsman_runs, extra_runs, total_runs,
    extras_type, is_wicket, player_dismissed_id, dismissal_kind, fielder_id
)
SELECT 
    c.match_id, c.inning, t1.team_id, t2.team_id, c.[over_no], c.ball,
    p1.player_id, p2.player_id, p3.player_id, c.batsman_runs, c.extra_runs, c.total_runs,
    c.extras_type, c.is_wicket, p4.player_id, c.dismissal_kind, p5.player_id    
FROM silver.deliveries_clean c
LEFT JOIN silver.dim_teams t1 ON c.batting_team = t1.team_name
LEFT JOIN silver.dim_teams t2 ON c.bowling_team = t2.team_name
LEFT JOIN silver.dim_players p1 ON c.batter = p1.player_name
LEFT JOIN silver.dim_players p2 ON c.bowler = p2.player_name
LEFT JOIN silver.dim_players p3 ON c.non_striker = p3.player_name
LEFT JOIN silver.dim_players p4 ON c.player_dismissed = p4.player_name
LEFT JOIN silver.dim_players p5 ON c.fielder = p5.player_name;
GO