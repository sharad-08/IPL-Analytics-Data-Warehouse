 -- ============================================================================
-- LAYER: BRONZE (RAW STAGING LAYER)
-- PURPOSE: Database Provisioning, Schema Separation, and Bulk CSV Ingestion
-- ============================================================================

USE master;
GO

-- 1. Defensive Environment Preparation: Drop Database if it Exists
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'IPL_Analytics_DW')
BEGIN 
    ALTER DATABASE IPL_Analytics_DW SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE IPL_Analytics_DW;
END;
GO 

-- 2. Create Analytics Data Warehouse Database
CREATE DATABASE IPL_Analytics_DW;
GO

USE IPL_Analytics_DW;
GO

-- 3. Provision Architectural Layer Schemas
CREATE SCHEMA bronze;
GO
CREATE SCHEMA silver;
GO
CREATE SCHEMA gold;
GO

-- ============================================================================
-- TABLE: bronze.matches
-- DESCRIPTION: Raw staging structure for tournament match logs
-- ============================================================================
IF OBJECT_ID('bronze.matches', 'U') IS NOT NULL
   DROP TABLE bronze.matches;
GO 

CREATE TABLE bronze.matches (
    id VARCHAR(20),                -- Match Identifier
    season VARCHAR(20),            -- Season boundaries (e.g., '2007/08')
    city VARCHAR(100),             -- Match host city
    match_date VARCHAR(20),        -- Staged as text to protect parsing boundaries
    match_type VARCHAR(50),        -- Match tier (e.g., 'League', 'Playoff')
    player_of_match VARCHAR(100),  -- MVP Player designation
    venue VARCHAR(150),            -- Stadium venue description
    team1 VARCHAR(100),            -- Competing Team 1
    team2 VARCHAR(100),            -- Competing Team 2
    toss_winner VARCHAR(100),      -- Toss winner team
    toss_decision VARCHAR(50),     -- Strategic decision ('bat' or 'field')
    winner VARCHAR(100),           -- Victorious team name
    result VARCHAR(50),            -- Margin category ('runs' or 'wickets')
    result_margin VARCHAR(50),     -- Victory delta or 'NA'
    target_runs VARCHAR(20),       -- Target score or 'NA'
    target_overs VARCHAR(20),      -- Target over constraints or 'NA'
    super_over VARCHAR(5),         -- Super over flag ('N', 'Y', or 'NA')
    method VARCHAR(20),            -- Alternative match system (e.g., 'D/L')
    umpire1 VARCHAR(100),          -- On-field Umpire 1 registry
    umpire2 VARCHAR(100)           -- On-field Umpire 2 registry
);
GO

-- ============================================================================
-- TABLE: bronze.deliveries
-- DESCRIPTION: Raw staging structure for ball-by-ball performance logs
-- ============================================================================
IF OBJECT_ID('bronze.deliveries', 'U') IS NOT NULL
   DROP TABLE bronze.deliveries;
GO 

CREATE TABLE bronze.deliveries (
    match_id VARCHAR(20),          -- Structural mapping to bronze.matches
    inning VARCHAR(5),             -- Inning identifier
    batting_team VARCHAR(200),     -- Innings batting franchise
    bowling_team VARCHAR(200),     -- Innings fielding franchise
    over_no VARCHAR(5),            -- Over progression marker
    ball VARCHAR(5),               -- Ball distribution index
    batter VARCHAR(100),           -- Active facing striker
    bowler VARCHAR(100),           -- Active delivering bowler
    non_striker VARCHAR(100),      -- Non-striking runner
    batsman_runs VARCHAR(5),       -- Runs generated off bat
    extra_runs VARCHAR(5),         -- Extra runs penalized
    total_runs VARCHAR(5),         -- Gross runs added on delivery
    extras_type VARCHAR(50),       -- Classification of extra runs
    is_wicket VARCHAR(5),          -- Wicket occurrence state
    player_dismissed VARCHAR(100), -- Terminated player record
    dismissal_kind VARCHAR(50),    -- Tactical dismissal description
    fielder VARCHAR(100)           -- Active supporting fielder
);
GO

-- ============================================================================
-- BULK DATA INGESTION SUITE
-- ============================================================================

-- Execute Match File Ingestion
TRUNCATE TABLE bronze.matches;
PRINT '>> Processing Pipeline: Ingesting data into bronze.matches';
BULK INSERT bronze.matches
FROM 'C:\Users\ASUS\Desktop\SQL\IPL_data\Matches.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    TABLOCK
);
PRINT '>> Success: bronze.matches ingestion complete';

-- Execute Deliveries File Ingestion
TRUNCATE TABLE bronze.deliveries;
PRINT '>> Processing Pipeline: Ingesting data into bronze.deliveries';
BULK INSERT bronze.deliveries
FROM 'C:\Users\ASUS\Desktop\SQL\IPL_data\Deliveries.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    TABLOCK
);
PRINT '>> Success: bronze.deliveries ingestion complete';
GO