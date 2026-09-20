/* ============================================================================
   FILE 03 - NORMALISED SCHEMA (1NF) AND ETL
   Engine  : PostgreSQL 16
   Run     : psql -d netflix_db -f 03_normalized_schema.sql
   Input   : netflix_clean
   Output  : 4 dimension tables + 4 bridge tables
   ----------------------------------------------------------------------------
   THE PROBLEM THIS SOLVES
   netflix_clean still violates first normal form. Four columns hold repeating
   groups inside a single cell:

       country   = 'India, United States'
       listed_in = 'Dramas, International Movies, Romantic Movies'

   Consequences of leaving it that way:
     1. GROUP BY country invents a category called 'India, United States',
        so India is undercounted. Exact-match filters see 972 Indian titles;
        the true figure is 1046, a 7.6% undercount.
     2. Every genre or country query needs runtime string parsing, which
        cannot use an index and must re-parse 8807 rows each time.
     3. There is nothing to join to, so relational questions like "which
        directors work across more than one genre" are unanswerable.

   THE FIX
   Split each repeating group into its own dimension table and connect it to
   the title with a bridge (junction) table holding a composite primary key.
   This is a classic many-to-many decomposition:

       dim_title --< bridge_title_genre >-- dim_genre
       dim_title --< bridge_title_country >-- dim_country
       dim_title --< bridge_title_director >-- dim_person
       dim_title --< bridge_title_cast >-- dim_person

   dim_person is deliberately SHARED between the director and cast bridges.
   A person is a person; the bridge defines the ROLE they played on a title.
   That one design choice is what makes "find people who both acted and
   directed" a two-line join instead of an impossible string comparison.

   NOTE ON ROW COUNTS
   Bridge tables have MORE rows than dim_title. That is expected and correct:
   one title with three genres contributes three bridge rows. It also means
   you can never SUM a bridge count to recover a title count - you must
   COUNT(DISTINCT show_id). This is the most common mistake made against a
   schema like this and is worth stating out loud in a review.
============================================================================ */

DROP TABLE IF EXISTS bridge_title_genre    CASCADE;
DROP TABLE IF EXISTS bridge_title_country  CASCADE;
DROP TABLE IF EXISTS bridge_title_director CASCADE;
DROP TABLE IF EXISTS bridge_title_cast     CASCADE;
DROP TABLE IF EXISTS dim_genre             CASCADE;
DROP TABLE IF EXISTS dim_country           CASCADE;
DROP TABLE IF EXISTS dim_person            CASCADE;
DROP TABLE IF EXISTS dim_title             CASCADE;

/* ---------------------------------------------------------------------------
   FACT / PRIMARY DIMENSION: one row per title, only 1:1 attributes.
   The four multi-value columns are deliberately absent.
--------------------------------------------------------------------------- */
CREATE TABLE dim_title (
    show_id        TEXT PRIMARY KEY,
    type           TEXT NOT NULL CHECK (type IN ('Movie', 'TV Show')),
    title          TEXT NOT NULL,
    release_year   INT  NOT NULL,
    date_added     DATE,
    year_added     INT,
    rating         TEXT,
    duration_value INT,
    duration_unit  TEXT,
    description    TEXT
);

INSERT INTO dim_title
SELECT show_id, type, title, release_year, date_added, year_added,
       rating, duration_value, duration_unit, description
FROM netflix_clean;

/* ---------------------------------------------------------------------------
   DIMENSIONS built from the split values.
   Pattern used throughout:
       TRIM(UNNEST(STRING_TO_ARRAY(col, ',')))
   STRING_TO_ARRAY turns 'a, b' into the array {a," b"}.
   UNNEST expands that array into one row per element.
   TRIM removes the space the delimiter left behind. Omitting TRIM is the
   single most common bug in this style of query.
--------------------------------------------------------------------------- */

CREATE TABLE dim_genre (
    genre_id   SERIAL PRIMARY KEY,
    genre_name TEXT NOT NULL UNIQUE
);
INSERT INTO dim_genre (genre_name)
SELECT DISTINCT TRIM(g)
FROM netflix_clean, UNNEST(STRING_TO_ARRAY(listed_in, ',')) AS g
WHERE TRIM(g) <> ''
ORDER BY 1;

CREATE TABLE dim_country (
    country_id   SERIAL PRIMARY KEY,
    country_name TEXT NOT NULL UNIQUE
);
INSERT INTO dim_country (country_name)
SELECT DISTINCT TRIM(c)
FROM netflix_clean, UNNEST(STRING_TO_ARRAY(country, ',')) AS c
WHERE TRIM(c) <> ''
ORDER BY 1;

CREATE TABLE dim_person (
    person_id   SERIAL PRIMARY KEY,
    person_name TEXT NOT NULL UNIQUE
);
/* UNION (not UNION ALL) deduplicates across the two roles, so a person who
   both directed and acted appears exactly once in the dimension. */
INSERT INTO dim_person (person_name)
SELECT DISTINCT TRIM(p) FROM (
    SELECT UNNEST(STRING_TO_ARRAY(director, ',')) AS p FROM netflix_clean
    UNION
    SELECT UNNEST(STRING_TO_ARRAY(casts,    ',')) AS p FROM netflix_clean
) s
WHERE TRIM(p) <> ''
ORDER BY 1;

/* ---------------------------------------------------------------------------
   BRIDGE TABLES. Composite primary key (show_id, dim_id) makes a duplicate
   pairing physically impossible, and the foreign keys guarantee no bridge row
   can ever point at a title or dimension value that does not exist.
--------------------------------------------------------------------------- */

CREATE TABLE bridge_title_genre (
    show_id  TEXT NOT NULL REFERENCES dim_title(show_id) ON DELETE CASCADE,
    genre_id INT  NOT NULL REFERENCES dim_genre(genre_id),
    PRIMARY KEY (show_id, genre_id)
);
INSERT INTO bridge_title_genre
SELECT DISTINCT n.show_id, g.genre_id
FROM netflix_clean n
CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(n.listed_in, ',')) AS x(val)
JOIN dim_genre g ON g.genre_name = TRIM(x.val);

CREATE TABLE bridge_title_country (
    show_id    TEXT NOT NULL REFERENCES dim_title(show_id) ON DELETE CASCADE,
    country_id INT  NOT NULL REFERENCES dim_country(country_id),
    PRIMARY KEY (show_id, country_id)
);
INSERT INTO bridge_title_country
SELECT DISTINCT n.show_id, c.country_id
FROM netflix_clean n
CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(n.country, ',')) AS x(val)
JOIN dim_country c ON c.country_name = TRIM(x.val);

CREATE TABLE bridge_title_director (
    show_id   TEXT NOT NULL REFERENCES dim_title(show_id) ON DELETE CASCADE,
    person_id INT  NOT NULL REFERENCES dim_person(person_id),
    PRIMARY KEY (show_id, person_id)
);
INSERT INTO bridge_title_director
SELECT DISTINCT n.show_id, p.person_id
FROM netflix_clean n
CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(n.director, ',')) AS x(val)
JOIN dim_person p ON p.person_name = TRIM(x.val);

CREATE TABLE bridge_title_cast (
    show_id   TEXT NOT NULL REFERENCES dim_title(show_id) ON DELETE CASCADE,
    person_id INT  NOT NULL REFERENCES dim_person(person_id),
    PRIMARY KEY (show_id, person_id)
);
INSERT INTO bridge_title_cast
SELECT DISTINCT n.show_id, p.person_id
FROM netflix_clean n
CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(n.casts, ',')) AS x(val)
JOIN dim_person p ON p.person_name = TRIM(x.val);

/* Indexes on the non-leading key column. The composite PK already indexes
   (show_id, x); these support the reverse lookup "all titles for this genre". */
CREATE INDEX idx_btg_genre   ON bridge_title_genre (genre_id);
CREATE INDEX idx_btc_country ON bridge_title_country (country_id);
CREATE INDEX idx_btd_person  ON bridge_title_director (person_id);
CREATE INDEX idx_btcast_person ON bridge_title_cast (person_id);

/* ---------------------------------------------------------------------------
   ETL VALIDATION
--------------------------------------------------------------------------- */

SELECT 'dim_title' AS tbl, COUNT(*) FROM dim_title              -- 8807
UNION ALL SELECT 'dim_genre',   COUNT(*) FROM dim_genre          -- 42
UNION ALL SELECT 'dim_country', COUNT(*) FROM dim_country        -- 122
UNION ALL SELECT 'dim_person',  COUNT(*) FROM dim_person
UNION ALL SELECT 'bridge_genre',    COUNT(*) FROM bridge_title_genre
UNION ALL SELECT 'bridge_country',  COUNT(*) FROM bridge_title_country
UNION ALL SELECT 'bridge_director', COUNT(*) FROM bridge_title_director
UNION ALL SELECT 'bridge_cast',     COUNT(*) FROM bridge_title_cast;

/* Coverage check: every title that HAD a value must appear in the bridge, and
   the count of titles with no bridge row must equal the original NULL count.
   This proves the ETL lost nothing. */
SELECT
    (SELECT COUNT(*) FROM dim_title t
      WHERE NOT EXISTS (SELECT 1 FROM bridge_title_country b WHERE b.show_id = t.show_id))
        AS titles_without_country,   -- must equal 831
    (SELECT COUNT(*) FROM dim_title t
      WHERE NOT EXISTS (SELECT 1 FROM bridge_title_director b WHERE b.show_id = t.show_id))
        AS titles_without_director,  -- must equal 2634
    (SELECT COUNT(*) FROM dim_title t
      WHERE NOT EXISTS (SELECT 1 FROM bridge_title_genre b WHERE b.show_id = t.show_id))
        AS titles_without_genre;     -- must equal 0

/* The undercount this schema fixes: exact-match India vs normalised India. */
SELECT
    (SELECT COUNT(*) FROM netflix_clean WHERE country = 'India') AS india_exact_match,   -- 972
    (SELECT COUNT(DISTINCT b.show_id)
       FROM bridge_title_country b
       JOIN dim_country c ON c.country_id = b.country_id
      WHERE c.country_name = 'India')                            AS india_normalised;   -- 1046

-- End of file 03
