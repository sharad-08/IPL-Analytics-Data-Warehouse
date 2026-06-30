# 🏏 Multi-Tier Cricket Analytics Warehouse (Medallion Architecture)

An enterprise-grade, end-to-end data engineering project that structures an optimization-focused relational Data Warehouse utilizing a three-tiered **Medallion Architecture (Bronze ➔ Silver ➔ Gold)**. The system ingests over a decade of raw, unformatted ball-by-ball tournament data, executes programmatic row-shifting alignment via recursive database calculations, maps a fully normalized **Star Schema Design**, and serves optimized metrics to Power BI over a high-performance **DirectQuery** layout.

---

## 🏗️ System Architecture Overview

The warehouse isolates staging data from semantic analytics through automated transformation layers to maintain complete database integrity and a zero-latency presentation experience.

* **🟫 Bronze Ingestion Layer (`bronze.matches` / `deliveries`):** Ingests raw text streams straight from local files into relaxed `VARCHAR` data fields. This append-only layer completely protects bulk ingestion jobs from failing due to unexpected format variations.
* **⬜ Silver Cleaning Layer (`silver.matches_clean` / `deliveries_clean`):** Implements an algorithmic **Recursive Common Table Expression (CTE)** that programmatically hunts down and fixes row-shifting errors caused by unescaped characters in text fields. This layer handles string trimming, date casting (`TRY_CAST`), and default value replacements.
* **⭐ Silver Relational Star Schema (`fact_` / `dim_` tables):** Breaks heavy textual entities into standalone dimension lookups (`dim_players`, `dim_teams`, `dim_venues`, `dim_umpires`) assigned low-overhead auto-incrementing integer **Surrogate Keys** (`IDENTITY(1,1)`). These keys map downstream to centralized transaction tables (`fact_matches`, `fact_deliveries`).
* **🟨 Gold Data Marts View Layer:** Encapsulates analytical queries inside structured SQL Server `VIEWS` to pre-calculate multi-grain values like player strike rates, bowling economies, and seasonal leaderboards.
* **📊 Power BI Interface:** Connects directly to the Gold database view layer via **DirectQuery Mode**, ensuring near-instant visual dashboard rendering with a zero local client memory footprint.

---

## 📂 Repository File Structure

```text
📁 IPL_Analytics_DW/
│
├── 📁 dataset/
│   ├── 📄 Deliveries.csv
│   ├── 📄 Matches.csv
│   └── 📄 ipl-matches2001 - 2022.csv
│
├── 📁 script/
│   ├── 📁 bronze/
│   │   └── 📜 bronze_layer_load.sql
│   │
│   ├── 📁 silver/
│   │   ├── 📜 silver_deliveries.sql
│   │   ├── 📜 silver_dimensions.sql
│   │   ├── 📜 silver_matches.sql
│   │   └── 📜 silver_matches_fact.sql
│   │
│   └── 📁 gold/
│       └── 📜 gold_reporting_marts.sql
│
├── 📁 leaderboard/
│   └── 📊 ALL3_leaderboard.pbix
│
├── 📁 doc/
│   └── 📕 IPL_Analytics_DW.pdf
└── 📝 README.md
