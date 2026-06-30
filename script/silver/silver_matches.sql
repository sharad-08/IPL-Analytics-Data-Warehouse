-- CREATE THE CLEAN BASE TABLE IN SILVER

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
    venue VARCHAR(500),          -- Expanded to handle concatenation
    team1 VARCHAR(200),
    team2 VARCHAR(200),
    toss_winner VARCHAR(200),
    toss_decision VARCHAR(200),  -- Expanded as requested
    winner VARCHAR(200),
    result VARCHAR(200),        -- Expanded as requested
    result_margin INT,          -- Converted to INT
    target_runs INT,            -- Converted to INT
    target_overs DECIMAL(4,1),  -- Converted to Decimal (e.g., 20.0)
    super_over VARCHAR(10),
    method VARCHAR(100),
    umpire1 VARCHAR(200),
    umpire2 VARCHAR(200)
);

TRUNCATE TABLE silver.matches_clean;
WITH RecursiveShift AS (
    -- 1. ANCHOR: Pull raw data and maximize varchar sizes for shifting safety
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

    -- 2. RECURSION: Apply column shifting step-by-step
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
    -- 3. Pick only the fully-shifted final variation of each row
    SELECT *, ROW_NUMBER() OVER (PARTITION BY id ORDER BY CurrentShift DESC) AS rn
    FROM RecursiveShift
)

-- 4. INSERT INTO SILVER with strict data type conversion
INSERT INTO silver.matches_clean
SELECT 
    TRY_CAST(id AS INT),
    season=year(match_date),
    city,
    match_date ,-- Adjust date format style (e.g., 103 for DD/MM/YYYY) if needed
    match_type,
    player_of_match,
    venue,
    team1,
    team2,
    toss_winner,
    toss_decision,
    winner,
    result,
    CASE WHEN result_margin = 'NA' THEN 0 ELSE TRY_CAST(result_margin AS INT) END,
    CASE WHEN target_runs = 'NA' THEN 0 ELSE TRY_CAST(target_runs AS INT) END,
    CASE WHEN target_overs = 'NA' THEN 0 ELSE TRY_CAST(target_overs AS DECIMAL(4,1)) END,
    super_over,
    method,
    umpire1,
    umpire2
FROM FinalFilter
WHERE rn = 1;


select * from silver.matches_clean




-- DIMENSION: TEAMS
IF OBJECT_ID('silver.dim_teams ', 'U') IS NOT NULL
    DROP TABLE silver.dim_teams ;
GO
CREATE TABLE silver.dim_teams (
    team_id INT IDENTITY(1,1) PRIMARY KEY,
    team_name VARCHAR(200) UNIQUE
);

-- DIMENSION: VENUES
IF OBJECT_ID('silver.dim_venues ', 'U') IS NOT NULL
    DROP TABLE silver.dim_venues;
GO
CREATE TABLE silver.dim_venues (
    venue_id INT IDENTITY(1,1) PRIMARY KEY,
    venue_name VARCHAR(300),
    city VARCHAR(200),
    CONSTRAINT UQ_Venue_City UNIQUE (venue_name, city)
);

-- DIMENSION: PLAYERS
IF OBJECT_ID('silver.dim_players ', 'U') IS NOT NULL
    DROP TABLE silver.dim_players ;
GO
CREATE TABLE silver.dim_players (
    player_id INT IDENTITY(1,1) PRIMARY KEY,
    player_name VARCHAR(200) UNIQUE,
    player_fullname VARCHAR(200) UNIQUE
);

--DIMENSION: UMPIRES
IF OBJECT_ID('silver.dim_umpires','U') IS NOT NULL
    DROP TABLE silver.dim_umpires;
GO
CREATE TABLE silver.dim_umpires(
    umpire_id INT IDENTITY(1,1) PRIMARY KEY,
    umpire_name VARCHAR(200) UNIQUE,
);

-- INSERT INTO A DIM_UMPIRE
INSERT INTO silver.dim_umpires (umpire_name)
select distinct umpire_name
 FROM (
    SELECT umpire1 as umpire_name  FROM silver.matches_clean WHERE umpire1 IS NOT NULL
    UNION
    SELECT umpire2 FROM silver.matches_clean WHERE umpire2 IS NOT NULL
) t;

    



----INSERT INTO A DIM TABLES 
-- Populate Teams (Combining all unique team column outputs)
INSERT INTO silver.dim_teams (team_name)
SELECT DISTINCT team_name 
FROM (
    SELECT team1 AS team_name FROM silver.matches_clean WHERE team1 IS NOT NULL
    UNION
    SELECT team2 FROM silver.matches_clean WHERE team2 IS NOT NULL
) t;

-- Populate Venues
INSERT INTO silver.dim_venues (venue_name, city)
SELECT DISTINCT venue, city 
FROM silver.matches_clean 
WHERE venue IS NOT NULL;

-- Populate Players
TRUNCATE TABLE  silver.dim_players
 INSERT INTO silver.dim_players (player_name, player_fullname)
VALUES
('A Chandila', 'Ajit Chandila'),
('A Kumble', 'Anil Kumble'),
('A Manohar', 'Abhinav Manohar'),
('A Mishra', 'Amit Mishra'),
('A Nehra', 'Ashish Nehra'),
('A Nortje', 'Anrich Nortje'),
('A Singh', 'Anureet Singh'),
('A Symonds', 'Andrew Symonds'),
('A Zampa', 'Adam Zampa'),
('AA Jhunjhunwala', 'Abhishek Jhunjhunwala'),
('AB de Villiers', 'Abraham Benjamin de Villiers'),
('AB Dinda', 'Ashok Dinda'),
('Abhishek Sharma', 'Abhishek Sharma'),
('AC Gilchrist', 'Adam Gilchrist'),
('AC Voges', 'Adam Voges'),
('AD Mascarenhas', 'Dimitri Mascarenhas'),
('AD Mathews', 'Angelo Mathews'),
('AD Russell', 'Andre Russell'),
('AJ Finch', 'Aaron Finch'),
('AJ Tye', 'Andrew Tye'),
('Akash Madhwal', 'Akash Madhwal'),
('AM Rahane', 'Ajinkya Rahane'),
('Anuj Rawat', 'Anuj Rawat'),
('AP Tare', 'Aditya Tare'),
('AR Patel', 'Axar Patel'),
('Arshdeep Singh', 'Arshdeep Singh'),
('AS Joseph', 'Alzarri Joseph'),
('AS Rajpoot', 'Ankit Rajpoot'),
('AT Rayudu', 'Ambati Rayudu'),
('Avesh Khan', 'Avesh Khan'),
('Azhar Mahmood', 'Azhar Mahmood'),
('B Kumar', 'Bhuvneshwar Kumar'),
('B Lee', 'Brett Lee'),
('B Sai Sudharsan', 'Sai Sudharsan'),
('B Stanlake', 'Billy Stanlake'),
('BA Bhatt', 'Bhargav Bhatt'),
('BA Stokes', 'Ben Stokes'),
('BB McCullum', 'Brendon McCullum'),
('BCJ Cutting', 'Ben Cutting'),
('BJ Hodge', 'Brad Hodge'),
('BW Hilfenhaus', 'Ben Hilfenhaus'),
('C Green', 'Cameron Green'),
('CA Lynn', 'Chris Lynn'),
('CH Gayle', 'Chris Gayle'),
('CH Morris', 'Chris Morris'),
('CJ Anderson', 'Corey Anderson'),
('CJ Jordan', 'Chris Jordan'),
('CL White', 'Cameron White'),
('CR Brathwaite', 'Carlos Brathwaite'),
('CRD Fernando', 'Dilhara Fernando'),
('CV Varun', 'Varun Chakaravarthy'),
('D Padikkal', 'Devdutt Padikkal'),
('DA Miller', 'David Miller'),
('DA Warner', 'David Warner'),
('DE Bollinger', 'Doug Bollinger'),
('DJ Bravo', 'Dwayne Bravo'),
('DJ Hooda', 'Deepak Hooda'),
('DJ Hussey', 'David Hussey'),
('DJG Sammy', 'Darren Sammy'),
('DL Chahar', 'Deepak Chahar'),
('DL Vettori', 'Daniel Vettori'),
('DP Conway', 'Devon Conway'),
('DP Nannes', 'Dirk Nannes'),
('DPMD Jayawardene', 'Mahela Jayawardene'),
('DR Sams', 'Daniel Sams'),
('DR Smith', 'Dwayne Smith'),
('DW Steyn', 'Dale Steyn'),
('E Lewis', 'Evin Lewis'),
('EJG Morgan', 'Eoin Morgan'),
('F du Plessis', 'Faf du Plessis'),
('G Gambhir', 'Gautam Gambhir'),
('GC Smith', 'Graeme Smith'),
('GD McGrath', 'Glenn McGrath'),
('GD Phillips', 'Glenn Phillips'),
('GH Vihari', 'Hanuma Vihari'),
('GJ Bailey', 'George Bailey'),
('GJ Maxwell', 'Glenn Maxwell'),
('Harbhajan Singh', 'Harbhajan Singh'),
('Harmeet Singh', 'Harmeet Singh'),
('Harpreet Brar', 'Harpreet Brar'),
('HC Brook', 'Harry Brook'),
('HF Gurney', 'Harry Gurney'),
('HH Gibbs', 'Herschelle Gibbs'),
('HH Pandya', 'Hardik Pandya'),
('HM Amla', 'Hashim Amla'),
('HV Patel', 'Harshal Patel'),
('I Sharma', 'Ishant Sharma'),
('IK Pathan', 'Irfan Pathan'),
('Imran Tahir', 'Imran Tahir'),
('Iqbal Abdulla', 'Iqbal Abdulla'),
('Ishan Kishan', 'Ishan Kishan'),
('J Botha', 'Johan Botha'),
('J Fraser-McGurk', 'Jake Fraser-McGurk'),
('J Little', 'Joshua Little'),
('J Theron', 'Juan ''Rusty'' Theron'), -- Single quotes escaped for SQL safety
('JA Morkel', 'Albie Morkel'),
('JC Archer', 'Jofra Archer'),
('JC Buttler', 'Jos Buttler'),
('JD Ryder', 'Jesse Ryder'),
('JD Unadkat', 'Jaydev Unadkat'),
('JDP Oram', 'Jacob Oram'),
('JEC Franklin', 'James Franklin'),
('JH Kallis', 'Jacques Kallis'),
('JJ Bumrah', 'Jasprit Bumrah'),
('JJ Roy', 'Jason Roy'),
('JM Bairstow', 'Jonny Bairstow'),
('JO Holder', 'Jason Holder'),
('JP Duminy', 'Jean-Paul Duminy'),
('JP Faulkner', 'James Faulkner'),
('JR Hazlewood', 'Josh Hazlewood'),
('K Rabada', 'Kagiso Rabada'),
('KA Pollard', 'Kieron Pollard'),
('Kartik Tyagi', 'Kartik Tyagi'),
('KC Sangakkara', 'Kumar Sangakkara'),
('KD Karthik', 'Dinesh Karthik'),
('KH Pandya', 'Krunal Pandya'),
('KK Ahmed', 'Khaleel Ahmed'),
('KK Cooper', 'Kevon Cooper'),
('KK Nair', 'Karun Nair'),
('KL Rahul', 'Lokesh Rahul'),
('KM Jadhav', 'Kedar Jadhav'),
('KMA Paul', 'Keemo Paul'),
('KMDN Kulasekara', 'Nuwan Kulasekara'),
('KP Pietersen', 'Kevin Pietersen'),
('KS Bharat', 'Kona Srikar Bharat'),
('KS Williamson', 'Kane Williamson'),
('Kuldeep Yadav', 'Kuldeep Yadav'),
('KV Sharma', 'Karn Sharma'),
('L Balaji', 'Lakshmipathy Balaji'),
('L Ngidi', 'Lungi Ngidi'),
('LH Ferguson', 'Lockie Ferguson'),
('LJ Wright', 'Luke Wright'),
('LMP Simmons', 'Lendl Simmons'),
('LR Shukla', 'Laxmi Ratan Shukla'),
('LRPL Taylor', 'Ross Taylor'),
('LS Livingstone', 'Liam Livingstone'),
('M Jansen', 'Marco Jansen'),
('M Kartik', 'Murali Kartik'),
('M Morkel', 'Morne Morkel'),
('M Muralitharan', 'Muttiah Muralitharan'),
('M Ntini', 'Makhaya Ntini'),
('M Pathirana', 'Matheesha Pathirana'),
('M Vijay', 'Murali Vijay'),
('M Vohra', 'Manan Vohra'),
('MA Agarwal', 'Mayank Agarwal'),
('MA Starc', 'Mitchell Starc'),
('MA Wood', 'Mark Wood'),
('Mandeep Singh', 'Mandeep Singh'),
('MC Henriques', 'Moises Henriques'),
('MD Mishra', 'Mohnish Mishra'),
('MEK Hussey', 'Michael Hussey'),
('MF Maharoof', 'Farveez Maharoof'),
('MG Johnson', 'Mitchell Johnson'),
('MJ Lumb', 'Michael Lumb'),
('MJ McClenaghan', 'Mitchell McClenaghan'),
('MK Pandey', 'Manish Pandey'),
('MK Tiwary', 'Manoj Tiwary'),
('ML Hayden', 'Matthew Hayden'),
('MM Ali', 'Moeen Ali'),
('MM Patel', 'Munaf Patel'),
('MM Sharma', 'Mohit Sharma'),
('MN Samuels', 'Marlon Samuels'),
('Mohammed Shami', 'Mohammed Shami'),
('Mohammed Siraj', 'Mohammed Siraj'),
('Mohsin Khan', 'Mohsin Khan'),
('MP Stoinis', 'Marcus Stoinis'),
('MP Yadav', 'Mayank Prakash Yadav'),
('MR Marsh', 'Mitchell Marsh'),
('MS Bisla', 'Manvinder Bisla'),
('MS Dhoni', 'Mahendra Singh Dhoni'),
('MS Gony', 'Manpreet Gony'),
('Mujeeb Ur Rahman', 'Mujeeb Ur Rahman'),
('Mukesh Choudhary', 'Mukesh Choudhary'),
('Mustafizur Rahman', 'Mustafizur Rahman'),
('MV Boucher', 'Mark Boucher'),
('N Pooran', 'Nicholas Pooran'),
('N Rana', 'Nitish Rana'),
('Nithish Kumar Reddy', 'Nitish Kumar Reddy'),
('NM Coulter-Nile', 'Nathan Coulter-Nile'),
('NT Ellis', 'Nathan Ellis'),
('NV Ojha', 'Naman Ojha'),
('OF Smith', 'Odean Smith'),
('P Kumar', 'Praveen Kumar'),
('P Negi', 'Pawan Negi'),
('P Parameswaran', 'Prasanth Parameswaran'),
('P Simran Singh', 'Prabhsimran Singh'),
('PA Patel', 'Parthiv Patel'),
('PC Valthaty', 'Paul Valthaty'),
('PD Collingwood', 'Paul Collingwood'),
('PD Salt', 'Phil Salt'),
('PJ Cummins', 'Pat Cummins'),
('PK Garg', 'Priyam Garg'),
('PN Mankad', 'Prerak Mankad'),
('PP Chawla', 'Piyush Chawla'),
('PP Ojha', 'Pragyan Ojha'),
('PP Shaw', 'Prithvi Shaw'),
('PV Tambe', 'Pravin Tambe'),
('PWH de Silva', 'Wanindu Hasaranga de Silva'),
('Q de Kock', 'Quinton de Kock'),
('R Ashwin', 'Ravichandran Ashwin'),
('R Bhatia', 'Rajat Bhatia'),
('R Dravid', 'Rahul Dravid'),
('R McLaren', 'Ryan McLaren'),
('R Parag', 'Riyan Parag'),
('R Sai Kishore', 'Ravisrinivasan Sai Kishore'),
('R Sharma', 'Rahul Sharma'),
('R Shepherd', 'Romario Shepherd'),
('R Tewatia', 'Rahul Tewatia'),
('R Vinay Kumar', 'Ranganath Vinay Kumar'),
('RA Jadeja', 'Ravindra Jadeja'),
('RA Tripathi', 'Rahul Tripathi'),
('Rashid Khan', 'Rashid Khan'),
('RD Chahar', 'Rahul Chahar'),
('RD Gaikwad', 'Ruturaj Gaikwad'),
('RE Levi', 'Richard Levi'),
('RG Sharma', 'Rohit Sharma'),
('RJ Harris', 'Ryan Harris'),
('RK Singh', 'Rinku Singh'),
('RM Patidar', 'Rajat Patidar'),
('RP Singh', 'Rudra Pratap Singh'),
('RR Pant', 'Rishabh Pant'),
('RR Rossouw', 'Rilee Rossouw'),
('RS Bopara', 'Ravi Bopara'),
('RV Uthappa', 'Robin Uthappa'),
('S Anirudha', 'Srikkanth Anirudha'),
('S Aravind', 'Sreenath Aravind'),
('S Badrinath', 'Subramaniam Badrinath'),
('S Dhawan', 'Shikhar Dhawan'),
('S Dube', 'Shivam Dube'),
('S Gopal', 'Shreyas Gopal'),
('S Nadeem', 'Shahbaz Nadeem'),
('S Sohal', 'Sunny Sohal'),
('S Sreesanth', 'Shanthakumaran Sreesanth'),
('SA Asnodkar', 'Swapnil Asnodkar'),
('SA Yadav', 'Suryakumar Yadav'),
('Sandeep Sharma', 'Sandeep Sharma'),
('SB Jakati', 'Shadab Jakati'),
('SB Wagh', 'Shrikant Wagh'),
('SC Ganguly', 'Sourav Ganguly'),
('SE Marsh', 'Shaun Marsh'),
('Shahbaz Ahmed', 'Shahbaz Ahmed'),
('Shakib Al Hasan', 'Shakib Al Hasan'),
('Shashank Singh', 'Shashank Singh'),
('Shivam Mavi', 'Shivam Mavi'),
('Shoaib Akhtar', 'Shoaib Akhtar'),
('Shubman Gill', 'Shubman Gill'),
('Sikandar Raza', 'Sikandar Raza'),
('Simarjeet Singh', 'Simarjeet Singh'),
('SK Raina', 'Suresh Raina'),
('SK Trivedi', 'Siddharth Trivedi'),
('SK Warne', 'Shane Warne'),
('SL Malinga', 'Lasith Malinga'),
('SM Curran', 'Sam Curran'),
('SM Katich', 'Simon Katich'),
('SM Pollock', 'Shaun Pollock'),
('SN Thakur', 'Shardul Thakur'),
('SO Hetmyer', 'Shimron Hetmyer'),
('Sohail Tanvir', 'Sohail Tanvir'),
('SP Goswami', 'Shreevats Goswami'),
('SP Narine', 'Sunil Narine'),
('SPD Smith', 'Steve Smith'),
('SR Tendulkar', 'Sachin Tendulkar'),
('SR Watson', 'Shane Watson'),
('SS Iyer', 'Shreyas Iyer'),
('ST Jayasuriya', 'Sanath Jayasuriya'),
('SV Samson', 'Sanju Samson'),
('SW Billings', 'Sam Billings'),
('TA Boult', 'Trent Boult'),
('TG Southee', 'Tim Southee'),
('TH David', 'Tim David'),
('TL Suman', 'Tirumalasetti Suman'),
('TM Dilshan', 'Tillakaratne Dilshan'),
('TM Head', 'Travis Head'),
('Umar Gul', 'Umar Gul'),
('Umran Malik', 'Umran Malik'),
('UT Yadav', 'Umesh Yadav'),
('V Kohli', 'Virat Kohli'),
('V Sehwag', 'Virender Sehwag'),
('VR Aaron', 'Varun Aaron'),
('VR Iyer', 'Venkatesh Iyer'),
('Washington Sundar', 'Washington Sundar'),
('WD Parnell', 'Wayne Parnell'),
('WG Jacks', 'Will Jacks'),
('WP Saha', 'Wriddhiman Saha'),
('WPUJC Vaas', 'Chaminda Vaas'),
('Yash Thakur', 'Yash Thakur'),
('YBK Jaiswal', 'Yashasvi Jaiswal'),
('YK Pathan', 'Yusuf Pathan'),
('YS Chahal', 'Yuzvendra Chahal'),
('Yuvraj Singh', 'Yuvraj Singh'),
('Z Khan', 'Zaheer Khan');
SELECT DISTINCT player_of_match 
FROM silver.matches_clean 
WHERE player_of_match IS NOT NULL;


SELECT * FROM silver.dim_players
select * from silver.dim_teams
select * from silver.dim_venues
select * from silver.dim_umpires

select * from bronze.deliveries




IF OBJECT_ID('silver.fact_matches','U') IS NOT NULL
    DROP TABLE silver.fact_matches
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


SELECT *  FROM silver.fact_matches
-- Populate using JOINs against your new dimensions
truncate table  silver.fact_matches
INSERT INTO silver.fact_matches
SELECT 
    m.id,
    m.season,
    v.venue_id,
    t1.team_id,
    t2.team_id,
    tw.team_id,
    m.toss_decision,
    w.team_id,
    p.player_id,
    m.result,
    m.result_margin,
    m.target_runs,
    m.target_overs,
    m.super_over,
    m.method,
    m.match_date,
    m.match_type,
    u1.umpire_id,
    u2.umpire_id
FROM silver.matches_clean m
LEFT JOIN silver.dim_venues v ON m.venue = v.venue_name AND m.city = v.city
LEFT JOIN silver.dim_teams t1 ON m.team1 = t1.team_name
LEFT JOIN silver.dim_teams t2 ON m.team2 = t2.team_name
LEFT JOIN silver.dim_teams tw ON m.toss_winner = tw.team_name
LEFT JOIN silver.dim_teams w  ON m.winner = w.team_name
LEFT JOIN silver.dim_players p ON m.player_of_match = p.player_name
LEFT JOIN silver.dim_umpires u1 ON m.umpire1=u1.umpire_name
LEFT JOIN silver.dim_umpires u2 ON m.umpire2=u2.umpire_name


use IPL_Analytics_DW

SELECT * FROM silver.fact_matches;

select * from silver.matches_clean 

select count(distinct(umpire_id)) from silver.dim_umpires