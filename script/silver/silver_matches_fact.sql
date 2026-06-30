-- ============================================================================
-- LAYER: SILVER MATCHES (DATA CLEANING & RECURSIVE REALIGNMENT)
-- PURPOSE: Correct Row-Shifting Corruptions and Map the Relational Match Fact Table
-- ============================================================================

USE IPL_Analytics_DW;
GO

-- 1. Create a clean intermediate surface for clean match parsing
IF OBJECT_ID('silver.matches_clean', 'U') IS NOT NULL
    DROP TABLE silver.matches_clean;
GO

CREATE TABLE silver.matches_clean (
    id INT PRIMARY KEY,
    season INT,
    city VARCHAR(200),
    match_date DATE,
    match_type VARCHAR(100),
    player_of_match VARCHAR(200),
    venue VARCHAR(500),         
    team1 VARCHAR(200),
    team2 VARCHAR(200),
    toss_winner VARCHAR(200),
    toss_decision VARCHAR(200), 
    winner VARCHAR(200),
    result VARCHAR(200),        
    result_margin INT,          
    target_runs INT,            
    target_overs DECIMAL(4,1),  
    super_over VARCHAR(10),
    method VARCHAR(100),
    umpire1 VARCHAR(200),
    umpire2 VARCHAR(200)
);
GO

-- 2. Execute Recursive Column Shifting Realignment Algorithm
TRUNCATE TABLE silver.matches_clean;

WITH RecursiveShift AS (
    -- ANCHOR MEMBER: Target raw fields and convert size constraints to VARCHAR(MAX)
    SELECT 
        id, season, city, match_date, match_type, player_of_match,
        CAST(venue AS VARCHAR(MAX)) AS venue,
        CAST(team1 AS VARCHAR(MAX)) AS team1,
        CAST(team2 AS VARCHAR(MAX)) AS team2,
        CAST(toss_winner AS VARCHAR(MAX)) AS toss_winner,
        CAST(toss_decision AS VARCHAR(MAX)) AS toss_decision,
        CAST(winner AS VARCHAR(MAX)) AS winner,
        CAST(result AS VARCHAR(MAX)) AS result,
        CAST(result_margin AS VARCHAR(MAX)) AS result_margin,
        CAST(target_runs AS VARCHAR(MAX)) AS target_runs,
        CAST(target_overs AS VARCHAR(MAX)) AS target_overs,
        CAST(super_over AS VARCHAR(MAX)) AS super_over,
        CAST(method AS VARCHAR(MAX)) AS method,
        CAST(umpire1 AS VARCHAR(MAX)) AS umpire1,
        CAST(umpire2 AS VARCHAR(MAX)) AS umpire2,
        0 AS CurrentShift
    FROM bronze.matches

    UNION ALL

    -- RECURSIVE MEMBER: Shift cell contents rightward if non-numeric values bleed into result_margin
    SELECT 
        id, season, city, match_date, match_type, player_of_match,
        CAST(venue + ',' + team1 AS VARCHAR(MAX)) AS venue,
        CAST(team2 AS VARCHAR(MAX)) AS team1,
        CAST(toss_winner AS VARCHAR(MAX)) AS team2,
        CAST(toss_decision AS VARCHAR(MAX)) AS toss_winner,
        CAST(winner AS VARCHAR(MAX)) AS toss_decision,
        CAST(result AS VARCHAR(MAX)) AS winner,
        CAST(result_margin AS VARCHAR(MAX)) AS result,
        CAST(target_runs AS VARCHAR(MAX)) AS result_margin,
        CAST(target_overs AS VARCHAR(MAX)) AS target_runs,
        CAST(super_over AS VARCHAR(MAX)) AS target_overs,
        CAST(method AS VARCHAR(MAX)) AS super_over,
        CAST(umpire1 AS VARCHAR(MAX)) AS method,
        CAST(CASE WHEN CHARINDEX(',', umpire2) > 0 THEN LEFT(umpire2, CHARINDEX(',', umpire2) - 1) ELSE umpire2 END AS VARCHAR(MAX)) AS umpire1,
        CAST(CASE WHEN CHARINDEX(',', umpire2) > 0 THEN SUBSTRING(umpire2, CHARINDEX(',', umpire2) + 1, LEN(umpire2)) ELSE '' END AS VARCHAR(MAX)) AS umpire2,
        CurrentShift + 1 AS CurrentShift
    FROM RecursiveShift
    WHERE TRY_CAST(result_margin AS FLOAT) IS NULL 
      AND result_margin <> 'NA'
      AND CurrentShift < 5
),
FinalFilter AS (
    -- Window partitioning to select the final corrected record variant
    SELECT *, ROW_NUMBER() OVER (PARTITION BY id ORDER BY CurrentShift DESC) AS rn
    FROM RecursiveShift
)
INSERT INTO silver.matches_clean
SELECT 
    TRY_CAST(id AS INT),
    CASE WHEN season LIKE '%/%' THEN TRY_CAST(LEFT(season, 4) AS INT) ELSE TRY_CAST(season AS INT) END,
    TRIM(city),
    TRY_CAST(match_date AS DATE),
    TRIM(match_type),
    TRIM(player_of_match),
    TRIM(venue), TRIM(team1), TRIM(team2), TRIM(toss_winner), TRIM(toss_decision), TRIM(winner), TRIM(result),
    CASE WHEN result_margin = 'NA' OR result_margin IS NULL THEN 0 ELSE TRY_CAST(result_margin AS INT) END,
    CASE WHEN target_runs = 'NA' OR target_runs IS NULL THEN 0 ELSE TRY_CAST(target_runs AS INT) END,
    CASE WHEN target_overs = 'NA' OR target_overs IS NULL THEN 0.0 ELSE TRY_CAST(target_overs AS DECIMAL(4,1)) END,
    TRIM(super_over), TRIM(method), TRIM(umpire1), TRIM(umpire2)
FROM FinalFilter 
WHERE rn = 1;
GO

-- ============================================================================
-- TABLE: silver.fact_matches
-- DESCRIPTION: Core Relational Star Schema Fact table tracking structural matches
-- ============================================================================
IF OBJECT_ID('silver.fact_matches', 'U') IS NOT NULL
    DROP TABLE silver.fact_matches;
GO

CREATE TABLE silver.fact_matches (
    match_id INT PRIMARY KEY,
    season INT,
    venue_id INT,
    team1_id INT,
    team2_id INT,
    toss_winner_id INT,
    toss_decision VARCHAR(50),
    winner_id INT,
    player_of_match_id INT,
    result VARCHAR(50),
    result_margin INT,
    target_runs INT,
    target_overs DECIMAL(4,1),
    super_over VARCHAR(10),
    method VARCHAR(100),
    match_date DATE,
    match_type VARCHAR(100),
    umpire1_id INT,
    umpire2_id INT
);
GO

-- Map dimensional surrogate integer values into the core Match Fact layer
TRUNCATE TABLE silver.fact_matches;

INSERT INTO silver.fact_matches
SELECT 
    m.id, m.season, v.venue_id, t1.team_id, t2.team_id, tw.team_id,
    m.toss_decision, w.team_id, p.player_id, m.result, m.result_margin,
    m.target_runs, m.target_overs, m.super_over, m.method, m.match_date, m.match_type,
    u1.umpire_id, u2.umpire_id
FROM silver.matches_clean m
LEFT JOIN silver.dim_venues v ON m.venue = v.venue_name AND ISNULL(m.city, 'Unknown City') = v.city
LEFT JOIN silver.dim_teams t1 ON m.team1 = t1.team_name
LEFT JOIN silver.dim_teams t2 ON m.team2 = t2.team_name
LEFT JOIN silver.dim_teams tw ON m.toss_winner = tw.team_name
LEFT JOIN silver.dim_teams w  ON m.winner = w.team_name
LEFT JOIN silver.dim_players p ON m.player_of_match = p.player_name
LEFT JOIN silver.dim_umpires u1 ON m.umpire1 = u1.umpire_name
LEFT JOIN silver.dim_umpires u2 ON m.umpire2 = u2.umpire_name;
GO