/* ============================================================================
   FILE 02 - CLEANING AND STRUCTURING (all 12 source fields)
   Engine  : PostgreSQL 16
   Run     : psql -d netflix_db -f 02_cleaning.sql
   Input   : netflix_raw (8807 rows, all TEXT)
   Output  : netflix_clean (8807 rows, typed, 16 columns)
   ----------------------------------------------------------------------------
   PRINCIPLE
   netflix_raw is never modified. Cleaning is a CREATE TABLE AS from raw, so the
   whole layer can be dropped and rebuilt from the same CSV and will produce
   byte-identical output. That is what makes the analysis reproducible.

   NO ROWS ARE DELETED. 8807 in, 8807 out. Missing values are made explicit as
   NULL rather than dropped, because dropping the 2634 director-less rows would
   silently bias every other answer in the project.

   TREATMENT APPLIED, FIELD BY FIELD
     show_id       trim; asserted unique; becomes PRIMARY KEY
     type          trim; constrained to 'Movie' / 'TV Show'
     title         trim; internal whitespace collapsed
     director      trim; separators normalised to ', '; '' -> NULL
     casts         trim; separators normalised to ', '; '' -> NULL
     country       trim; separators normalised to ', '; '' -> NULL
     date_added    text -> DATE; year_added and month_added derived
     release_year  text -> INT; range-checked
     rating        3 misplaced duration values removed; 'UR' folded into 'NR'
     duration      split into duration_value INT + duration_unit TEXT
     listed_in     trim; separators normalised to ', '
     description   trim; internal whitespace collapsed
   ============================================================================ */

DROP TABLE IF EXISTS netflix_clean CASCADE;

CREATE TABLE netflix_clean AS
WITH trimmed AS (
    /* STEP 1 - whitespace and empty-string handling.
       TRIM removes leading/trailing spaces. NULLIF(...,'') turns an empty cell
       into a real NULL, so COUNT() and IS NULL behave honestly.
       regexp_replace('\s+',' ','g') collapses internal runs of whitespace,
       including newlines that appear inside some descriptions. */
    SELECT
        NULLIF(TRIM(show_id), '')                                   AS show_id,
        NULLIF(TRIM(type), '')                                      AS type,
        NULLIF(regexp_replace(TRIM(title), '\s+', ' ', 'g'), '')    AS title,
        NULLIF(TRIM(director), '')                                  AS director,
        NULLIF(TRIM(casts), '')                                     AS casts,
        NULLIF(TRIM(country), '')                                   AS country,
        NULLIF(TRIM(date_added), '')                                AS date_added,
        NULLIF(TRIM(release_year), '')                              AS release_year,
        NULLIF(TRIM(rating), '')                                    AS rating,
        NULLIF(TRIM(duration), '')                                  AS duration,
        NULLIF(TRIM(listed_in), '')                                 AS listed_in,
        NULLIF(regexp_replace(TRIM(description), '\s+', ' ', 'g'), '') AS description
    FROM netflix_raw
),
repaired AS (
    /* STEP 2 - repair the column-shift defect.
       In 3 rows (s5542, s5795, s5814) the duration value was written into the
       rating column and duration was left blank. Detection is by pattern, not
       by hard-coded show_id, so the fix still works if the source is refreshed
       and different rows are affected.

       Decision: move the value to duration, set rating to NULL. We do NOT
       invent a certification we cannot know. */
    SELECT
        show_id, type, title, director, casts, country, date_added, release_year,
        CASE WHEN rating ILIKE '%min%' THEN NULL ELSE rating END       AS rating,
        CASE WHEN rating ILIKE '%min%' THEN rating ELSE duration END   AS duration,
        listed_in, description
    FROM trimmed
),
separators AS (
    /* STEP 3 - normalise the multi-value delimiters.
       Source cells look like 'India,  United States' or 'Dramas ,Comedies'.
       Rewriting every '\s*,\s*' to exactly ', ' means that later, when these
       strings are split into arrays, no element carries stray whitespace.
       Skipping this step causes 'Dramas' and ' Dramas' to be counted as two
       different genres, which silently fragments every genre total.

       A second defect handled here: some cells begin or end with a stray
       delimiter, e.g. s194 country = ', South Korea' and s366 = ', France,
       Algeria'. Splitting those produces 7 empty tokens across the dataset,
       which would become a phantom country named ''. The outer
       regexp_replace strips leading and trailing commas before the split. */
    SELECT
        show_id, type, title,
        regexp_replace(regexp_replace(director,  '\s*,\s*', ', ', 'g'), '^,\s*|,\s*$', '', 'g') AS director,
        regexp_replace(regexp_replace(casts,     '\s*,\s*', ', ', 'g'), '^,\s*|,\s*$', '', 'g') AS casts,
        regexp_replace(regexp_replace(country,   '\s*,\s*', ', ', 'g'), '^,\s*|,\s*$', '', 'g') AS country,
        date_added, release_year, rating, duration,
        regexp_replace(regexp_replace(listed_in, '\s*,\s*', ', ', 'g'), '^,\s*|,\s*$', '', 'g') AS listed_in,
        description
    FROM repaired
)
/* STEP 4 - type casting and structural derivation. */
SELECT
    show_id,
    type,
    title,
    director,
    casts,
    country,

    /* date_added: free text 'September 25, 2021' -> DATE.
       10 rows have no value and stay NULL. We do not guess them. */
    TO_DATE(date_added, 'Month DD, YYYY')                       AS date_added,
    EXTRACT(YEAR  FROM TO_DATE(date_added, 'Month DD, YYYY'))::INT AS year_added,
    EXTRACT(MONTH FROM TO_DATE(date_added, 'Month DD, YYYY'))::INT AS month_added,

    release_year::INT                                           AS release_year,

    /* rating: 'UR' (unrated) and 'NR' (not rated) are the same real-world
       category held under two labels. Folding them prevents the top-N rating
       query from splitting one group across two rows. */
    CASE WHEN rating = 'UR' THEN 'NR' ELSE rating END           AS rating,

    /* duration: split one mixed-unit text column into a number and a unit.
       SPLIT_PART(duration,' ',1) takes the text before the first space.
       This is the single most important structural fix in the project: it
       makes duration sortable and comparable, but only WITHIN a unit, which is
       why every runtime query still filters on type. */
    SPLIT_PART(duration, ' ', 1)::INT                           AS duration_value,
    CASE WHEN duration ILIKE '%season%' THEN 'seasons'
         WHEN duration ILIKE '%min%'    THEN 'minutes'
         ELSE NULL END                                          AS duration_unit,

    listed_in,
    description
FROM separators;

/* ----------------------------------------------------------------------------
   CONSTRAINTS - cleaning is only trustworthy if the database enforces it.
   If any assumption above is wrong, these statements fail loudly.
---------------------------------------------------------------------------- */

ALTER TABLE netflix_clean ALTER COLUMN show_id SET NOT NULL;
ALTER TABLE netflix_clean ADD CONSTRAINT pk_netflix_clean PRIMARY KEY (show_id);
ALTER TABLE netflix_clean ADD CONSTRAINT chk_type
    CHECK (type IN ('Movie', 'TV Show'));
ALTER TABLE netflix_clean ADD CONSTRAINT chk_release_year
    CHECK (release_year BETWEEN 1900 AND 2100);
ALTER TABLE netflix_clean ADD CONSTRAINT chk_duration_unit
    CHECK (duration_unit IN ('minutes', 'seasons') OR duration_unit IS NULL);
/* A film is never measured in seasons and a series is never measured in
   minutes. Asserting it means the mixed-unit defect can never silently return. */
ALTER TABLE netflix_clean ADD CONSTRAINT chk_unit_matches_type
    CHECK (duration_unit IS NULL
           OR (type = 'Movie'   AND duration_unit = 'minutes')
           OR (type = 'TV Show' AND duration_unit = 'seasons'));

CREATE INDEX idx_clean_type         ON netflix_clean (type);
CREATE INDEX idx_clean_release_year ON netflix_clean (release_year);
CREATE INDEX idx_clean_year_added   ON netflix_clean (year_added);

/* ----------------------------------------------------------------------------
   POST-CLEAN VALIDATION
---------------------------------------------------------------------------- */

-- No rows lost. Expected: 8807 = 8807
SELECT
    (SELECT COUNT(*) FROM netflix_raw)   AS raw_rows,
    (SELECT COUNT(*) FROM netflix_clean) AS clean_rows;

-- The shift defect is gone: 0 ratings containing 'min', 0 NULL durations
-- for rows that had a recoverable value.
SELECT
    COUNT(*) FILTER (WHERE rating ILIKE '%min%')      AS ratings_with_min,   -- 0
    COUNT(*) FILTER (WHERE duration_value IS NULL)    AS null_duration_value -- 0
FROM netflix_clean;

-- Missingness after cleaning: unchanged where it was genuine, which is correct.
-- We fixed structure, we did not fabricate content.
SELECT
    COUNT(*) - COUNT(director)   AS null_director,   -- 2634
    COUNT(*) - COUNT(casts)      AS null_cast,       -- 825
    COUNT(*) - COUNT(country)    AS null_country,    -- 831
    COUNT(*) - COUNT(date_added) AS null_date_added, -- 10
    COUNT(*) - COUNT(rating)     AS null_rating      -- 7 (4 original + 3 repaired)
FROM netflix_clean;

-- Unit split landed correctly against content type.
SELECT type, duration_unit, COUNT(*) AS n, MIN(duration_value) AS min_v, MAX(duration_value) AS max_v
FROM netflix_clean
GROUP BY 1, 2 ORDER BY 1, 2;

-- Snapshot boundary on the typed column, used by every "last N years" query.
SELECT MIN(date_added) AS earliest, MAX(date_added) AS snapshot_date
FROM netflix_clean;                                   -- 2008-01-01 .. 2021-09-25

-- End of file 02
