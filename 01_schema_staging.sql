/* ============================================================================
   FILE 01 - STAGING SCHEMA AND RAW LOAD
   Project : Netflix Catalog Insights Using SQL
   Engine  : PostgreSQL 16
   Run     : psql -d netflix_db -f 01_schema_staging.sql
   ----------------------------------------------------------------------------
   WHY A STAGING TABLE?
   The source file is a public Kaggle export of Netflix's catalogue. It contains
   known defects: blank cells, values sitting in the wrong column, a mixed-unit
   duration field, and four columns that pack multiple values into one cell as
   comma-separated text.

   If we load straight into typed columns, a single bad row aborts the whole
   COPY and we lose visibility of WHICH row was bad. So every column here is
   declared TEXT. The load is guaranteed to succeed, the defects survive intact,
   and we can measure them before deciding how to treat them (file 02).

   This is the standard extract-then-transform pattern: land raw, fix in SQL,
   keep the raw layer immutable so results stay reproducible.
============================================================================ */

DROP TABLE IF EXISTS netflix_raw CASCADE;

CREATE TABLE netflix_raw (
    show_id      TEXT,   -- primary identifier, e.g. 's1'
    type         TEXT,   -- 'Movie' or 'TV Show'
    title        TEXT,
    director     TEXT,   -- COMMA-SEPARATED, may hold several names
    casts        TEXT,   -- COMMA-SEPARATED. Named 'casts' because CAST is a
                         -- reserved keyword in SQL and 'cast' would need quoting
    country      TEXT,   -- COMMA-SEPARATED, co-productions list every country
    date_added   TEXT,   -- free text, format 'September 25, 2021'
    release_year TEXT,   -- loaded as text here, cast to INT in file 02
    rating       TEXT,   -- certification, e.g. 'TV-MA'. Contains 3 bad values
    duration     TEXT,   -- MIXED UNITS: '90 min' for films, '2 Seasons' for TV
    listed_in    TEXT,   -- COMMA-SEPARATED genre tags
    description  TEXT
);

/* ----------------------------------------------------------------------------
   LOAD
   \copy is a psql client-side command, so it reads the file from wherever you
   run psql (the repo root) and needs no superuser rights. Run psql from the
   folder that contains netflix_titles.csv.

   The column list is positional: it maps file column 5 ('cast') onto our
   'casts' column. HEADER true skips the header row.
---------------------------------------------------------------------------- */

\copy netflix_raw (show_id, type, title, director, casts, country, date_added, release_year, rating, duration, listed_in, description) FROM 'netflix_titles.csv' WITH (FORMAT csv, HEADER true, QUOTE '"');

/* ----------------------------------------------------------------------------
   LOAD VERIFICATION - expected: 8807 rows, 12 columns
---------------------------------------------------------------------------- */

SELECT COUNT(*) AS rows_loaded FROM netflix_raw;                    -- 8807

SELECT COUNT(*) AS column_count
FROM information_schema.columns
WHERE table_name = 'netflix_raw';                                   -- 12

/* ----------------------------------------------------------------------------
   DATA PROFILE - run BEFORE cleaning, so we know what we are fixing.
   COUNT(*) counts rows; COUNT(col) skips NULLs. The gap between them is the
   missingness in that column. This single query is the justification for
   every decision taken in file 02.
---------------------------------------------------------------------------- */

SELECT
    COUNT(*)                                  AS total_rows,        -- 8807
    COUNT(*) - COUNT(show_id)                 AS null_show_id,      -- 0
    COUNT(*) - COUNT(type)                    AS null_type,         -- 0
    COUNT(*) - COUNT(title)                   AS null_title,        -- 0
    COUNT(*) - COUNT(director)                AS null_director,     -- 2634
    COUNT(*) - COUNT(casts)                   AS null_cast,         -- 825
    COUNT(*) - COUNT(country)                 AS null_country,      -- 831
    COUNT(*) - COUNT(date_added)              AS null_date_added,   -- 10
    COUNT(*) - COUNT(release_year)            AS null_release_year, -- 0
    COUNT(*) - COUNT(rating)                  AS null_rating,       -- 4
    COUNT(*) - COUNT(duration)                AS null_duration,     -- 3
    COUNT(*) - COUNT(listed_in)               AS null_listed_in,    -- 0
    COUNT(*) - COUNT(description)             AS null_description   -- 0
FROM netflix_raw;

-- Uniqueness of the intended key. Expected 0 duplicates, but never assume it.
SELECT COUNT(*) - COUNT(DISTINCT show_id) AS duplicate_show_ids FROM netflix_raw;

-- DEFECT 1: three rows have a duration value stored in the rating column.
-- These are the rows that would crash any ::INT cast on duration.
SELECT show_id, type, rating, duration
FROM netflix_raw
WHERE rating ILIKE '%min%';                   -- s5542, s5795, s5814

-- DEFECT 2: duration carries two incompatible units in one column.
SELECT
    CASE WHEN duration ILIKE '%min%'    THEN 'minutes'
         WHEN duration ILIKE '%season%' THEN 'seasons'
         ELSE 'unparseable' END AS duration_unit,
    COUNT(*) AS n
FROM netflix_raw
GROUP BY 1 ORDER BY 2 DESC;

-- DEFECT 3: multi-value columns. Any GROUP BY on these raw columns is wrong,
-- because 'India, United States' becomes its own fake category.
SELECT
    COUNT(*) FILTER (WHERE country   LIKE '%,%') AS rows_multi_country, -- 1320
    COUNT(*) FILTER (WHERE listed_in LIKE '%,%') AS rows_multi_genre,   -- 6787
    COUNT(*) FILTER (WHERE director  LIKE '%,%') AS rows_multi_director,
    COUNT(*) FILTER (WHERE casts     LIKE '%,%') AS rows_multi_cast
FROM netflix_raw;

-- Snapshot boundary. The catalogue is frozen in time, so all "last N years"
-- logic must be measured from this date, NOT from CURRENT_DATE.
SELECT
    MIN(TO_DATE(date_added, 'Month DD, YYYY')) AS earliest_added,   -- 2008-01-01
    MAX(TO_DATE(date_added, 'Month DD, YYYY')) AS latest_added      -- 2021-09-25
FROM netflix_raw
WHERE date_added IS NOT NULL;

-- End of file 01
