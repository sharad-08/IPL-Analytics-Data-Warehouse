-- ============================================================================
-- LAYER: SILVER DIMENSIONS (NORMALIZATION & MASTER LOOKUP DATA)
-- PURPOSE: Extract Distinct Entities and Assign Automated Surrogate Keys
-- ============================================================================

USE IPL_Analytics_DW;
GO

-- ============================================================================
-- TABLE: silver.dim_teams
-- DESCRIPTION: Master dimension for tracking verified unique cricket franchises
-- ============================================================================
IF OBJECT_ID('silver.dim_teams', 'U') IS NOT NULL
    DROP TABLE silver.dim_teams;
GO

CREATE TABLE silver.dim_teams (
    team_id INT IDENTITY(1,1) PRIMARY KEY,
    team_name VARCHAR(200) UNIQUE NOT NULL
);
GO

-- Populate Distinct Master Teams from both Home and Away slots
INSERT INTO silver.dim_teams (team_name)
SELECT DISTINCT TRIM(team_name)
FROM (
    SELECT team1 AS team_name FROM bronze.matches WHERE team1 IS NOT NULL AND team1 <> 'NA'
    UNION
    SELECT team2 FROM bronze.matches WHERE team2 IS NOT NULL AND team2 <> 'NA'
) DistinctTeams;
GO

-- ============================================================================
-- TABLE: silver.dim_venues
-- DESCRIPTION: Tracks playing grounds isolated dynamically across cities
-- ============================================================================
IF OBJECT_ID('silver.dim_venues', 'U') IS NOT NULL
    DROP TABLE silver.dim_venues;
GO

CREATE TABLE silver.dim_venues (
    venue_id INT IDENTITY(1,1) PRIMARY KEY,
    venue_name VARCHAR(300) NOT NULL,
    city VARCHAR(200) NOT NULL,
    CONSTRAINT UQ_Venue_City UNIQUE (venue_name, city)
);
GO

-- Populate unique grounds configuration maps
INSERT INTO silver.dim_venues (venue_name, city)
SELECT DISTINCT TRIM(venue), ISNULL(TRIM(city), 'Unknown City')
FROM bronze.matches
WHERE venue IS NOT NULL AND venue <> 'NA';
GO

-- ============================================================================
-- TABLE: silver.dim_players
-- DESCRIPTION: Master record index keeping unique player tracking profiles
-- ============================================================================
IF OBJECT_ID('silver.dim_players', 'U') IS NOT NULL
    DROP TABLE silver.dim_players;
GO

CREATE TABLE silver.dim_players (
    player_id INT IDENTITY(1,1) PRIMARY KEY,
    player_name VARCHAR(200) UNIQUE NOT NULL,
    player_fullname VARCHAR(200) NOT NULL
);
GO

-- Initial pull of unique playing athletes from structural match MVPs
INSERT INTO silver.dim_players (player_name, player_fullname)
SELECT DISTINCT TRIM(player_of_match), TRIM(player_of_match)
FROM bronze.matches
WHERE player_of_match IS NOT NULL AND player_of_match <> 'NA';
GO

-- ============================================================================
-- TABLE: silver.dim_umpires
-- DESCRIPTION: Standalone dictionary tracking referee assignments
-- ============================================================================
IF OBJECT_ID('silver.dim_umpires', 'U') IS NOT NULL
    DROP TABLE silver.dim_umpires;
GO

CREATE TABLE silver.dim_umpires (
    umpire_id INT IDENTITY(1,1) PRIMARY KEY,
    umpire_name VARCHAR(200) UNIQUE NOT NULL
);
GO

-- Extract unique umpires across row boundaries safely
INSERT INTO silver.dim_umpires (umpire_name)
SELECT DISTINCT TRIM(umpire_name)
FROM (
    SELECT umpire1 AS umpire_name FROM bronze.matches WHERE umpire1 IS NOT NULL AND umpire1 <> 'NA'
    UNION
    SELECT umpire2 FROM bronze.matches WHERE umpire2 IS NOT NULL AND umpire2 <> 'NA'
) DistinctUmpires;
GO