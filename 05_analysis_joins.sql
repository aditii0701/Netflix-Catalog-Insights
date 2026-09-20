/* ============================================================================
   FILE 05 - RELATIONAL ANALYSIS ON THE NORMALISED SCHEMA (12 queries)
   Engine  : PostgreSQL 16
   Run     : psql -d netflix_db -f 05_analysis_joins.sql
   Input   : dim_title, dim_genre, dim_country, dim_person, 4 bridge tables
   ----------------------------------------------------------------------------
   WHY THIS FILE EXISTS
   File 04 answers every question against the single denormalised table, which
   forces runtime string parsing and cannot answer relational questions at all.
   This file answers the same kind of questions by joining, and then answers
   several that the flat table simply cannot.

   JOIN TYPES DEMONSTRATED
     INNER JOIN      J1, J2, J3, J4, J6, J8, J9, J10, J11
     LEFT JOIN       J5, J7
     ANTI-JOIN       J5  (LEFT JOIN ... WHERE right side IS NULL)
     SELF JOIN       J8  (bridge joined to itself to find country pairs)
     FULL OUTER JOIN J6  (keeps genres present in only one of two markets)
     SEMI-JOIN       J12 (EXISTS)

   THE RULE THAT MATTERS MOST
   A bridge table multiplies rows. dim_title has 8807 rows but
   bridge_title_genre has 19323, because a title with three genre tags
   contributes three rows. So after any bridge join, COUNT(*) counts
   PAIRINGS, not titles. Every title count below uses
   COUNT(DISTINCT t.show_id). Getting this wrong is the classic fan-out bug
   and it inflates results silently rather than throwing an error.
============================================================================ */

/* ---------------------------------------------------------------------------
   J1. TOP 5 GENRES - the same answer as Q9 in file 04, reached by joining
   instead of parsing strings at runtime. Same numbers, and this version can
   use an index on genre_id.
   RESULT: International Movies 2752, Dramas 2427, Comedies 1674,
           International TV Shows 1351, Documentaries 869
--------------------------------------------------------------------------- */
SELECT
    g.genre_name,
    COUNT(DISTINCT t.show_id) AS titles
FROM dim_genre g
JOIN bridge_title_genre b ON b.genre_id = g.genre_id
JOIN dim_title t          ON t.show_id  = b.show_id
GROUP BY g.genre_name
ORDER BY titles DESC
LIMIT 5;

/* ---------------------------------------------------------------------------
   J2. TOP 20 PROLIFIC DIRECTORS with their dominant genre.
   Technique: a CTE to rank each director's genres, then an INNER JOIN of two
   CTEs. Answering this against the flat table would need the director string
   and the genre string parsed and cross-multiplied in the same pass.
   RESULT: Rajiv Chilaka 22 titles, dominant genre Children & Family Movies;
           Jan Suter 21, Stand-Up Comedy; Raul Campos 19, Stand-Up Comedy.
--------------------------------------------------------------------------- */
WITH director_titles AS (
    SELECT p.person_id, p.person_name, COUNT(DISTINCT b.show_id) AS titles
    FROM dim_person p
    JOIN bridge_title_director b ON b.person_id = p.person_id
    GROUP BY p.person_id, p.person_name
),
director_genre AS (
    SELECT
        b.person_id,
        g.genre_name,
        COUNT(*) AS n,
        ROW_NUMBER() OVER (PARTITION BY b.person_id ORDER BY COUNT(*) DESC, g.genre_name) AS rn
    FROM bridge_title_director b
    JOIN bridge_title_genre bg ON bg.show_id = b.show_id
    JOIN dim_genre g           ON g.genre_id = bg.genre_id
    GROUP BY b.person_id, g.genre_name
)
SELECT
    dt.person_name  AS director,
    dt.titles,
    dg.genre_name   AS dominant_genre
FROM director_titles dt
JOIN director_genre dg ON dg.person_id = dt.person_id AND dg.rn = 1
ORDER BY dt.titles DESC, dt.person_name
LIMIT 20;

/* ---------------------------------------------------------------------------
   J3. FORMAT MIX WITHIN EACH GENRE - which genres are film territory and
   which are series territory. Conditional aggregation over a join.
   RESULT: a genuine surprise, and the most useful structural finding in this
   file. Every genre tag is 100% film or 100% series, never mixed. The
   taxonomy is format-partitioned: 'Dramas' is film-only and 'TV Dramas' is
   its series counterpart, 'Comedies' pairs with 'TV Comedies',
   'Documentaries' with 'Docuseries'. So you cannot compare a genre across
   formats without first mapping the tag pairs, and a naive
   'most popular genre' ranking is really two separate rankings stacked on
   top of each other. This is why International Movies (2752) outranks
   International TV Shows (1351) - it is not one genre being twice as popular,
   it is the film catalogue being larger.
--------------------------------------------------------------------------- */
SELECT
    g.genre_name,
    COUNT(DISTINCT t.show_id)                                          AS titles,
    COUNT(DISTINCT t.show_id) FILTER (WHERE t.type = 'Movie')          AS movies,
    COUNT(DISTINCT t.show_id) FILTER (WHERE t.type = 'TV Show')        AS tv_shows,
    ROUND(100.0 * COUNT(DISTINCT t.show_id) FILTER (WHERE t.type = 'Movie')
          / COUNT(DISTINCT t.show_id), 1)                              AS movie_pct
FROM dim_genre g
JOIN bridge_title_genre b ON b.genre_id = g.genre_id
JOIN dim_title t          ON t.show_id  = b.show_id
GROUP BY g.genre_name
HAVING COUNT(DISTINCT t.show_id) >= 200
ORDER BY titles DESC;

/* ---------------------------------------------------------------------------
   J4. GENRE RANGE PER DIRECTOR - directors working across the most distinct
   genres, among those with at least 5 titles.
   Technique: a three-table join with HAVING on two different aggregates.
   HAVING filters groups after aggregation; WHERE filters rows before it,
   which is why the title threshold cannot go in WHERE.
   RESULT: Martin Scorsese and Anurag Kashyap top the list at 9 distinct
   genre tags each, followed by Priyadarshan, Vishal Bhardwaj and
   Abhishek Chaubey at 8.
--------------------------------------------------------------------------- */
SELECT
    p.person_name                    AS director,
    COUNT(DISTINCT b.show_id)        AS titles,
    COUNT(DISTINCT g.genre_id)       AS distinct_genres,
    STRING_AGG(DISTINCT g.genre_name, ', ' ORDER BY g.genre_name) AS genres
FROM dim_person p
JOIN bridge_title_director b ON b.person_id = p.person_id
JOIN bridge_title_genre bg   ON bg.show_id  = b.show_id
JOIN dim_genre g             ON g.genre_id  = bg.genre_id
GROUP BY p.person_name
HAVING COUNT(DISTINCT b.show_id) >= 5
ORDER BY distinct_genres DESC, titles DESC
LIMIT 10;

/* ---------------------------------------------------------------------------
   J5. ANTI-JOIN - titles with no director credited, by type.
   LEFT JOIN keeps every row from dim_title; rows with no match get NULLs on
   the right; filtering for IS NULL on the right-hand key therefore returns
   exactly the non-matching rows. This is the anti-join pattern.
   RESULT: 2634 titles, 2446 of them series (92.9%). Series are credited to
   creators, not directors, so the gap is structural, not random missingness.
--------------------------------------------------------------------------- */
SELECT
    t.type,
    COUNT(*) AS titles_without_director
FROM dim_title t
LEFT JOIN bridge_title_director b ON b.show_id = t.show_id
WHERE b.show_id IS NULL
GROUP BY t.type
ORDER BY titles_without_director DESC;

/* ---------------------------------------------------------------------------
   J6. FULL OUTER JOIN - genre mix of India versus the United States.
   A FULL OUTER JOIN is required because some genres exist in one market and
   not the other; an INNER JOIN would silently drop exactly the rows that make
   the comparison interesting. COALESCE recovers the genre name from whichever
   side is present.
   RESULT: India is dominated by International Movies (864 of 1046 titles)
   and Dramas (662). The US leads on Documentaries (512 vs 27) and
   Children & Family Movies (390 vs 26). Note 'International' is defined
   relative to a US viewer, which is why it is India's largest tag and only
   the US's fifth.
--------------------------------------------------------------------------- */
WITH genre_by_country AS (
    SELECT c.country_name, g.genre_name, COUNT(DISTINCT t.show_id) AS titles
    FROM dim_title t
    JOIN bridge_title_country bc ON bc.show_id = t.show_id
    JOIN dim_country c           ON c.country_id = bc.country_id
    JOIN bridge_title_genre bg   ON bg.show_id = t.show_id
    JOIN dim_genre g             ON g.genre_id = bg.genre_id
    WHERE c.country_name IN ('India', 'United States')
    GROUP BY c.country_name, g.genre_name
),
ind AS (SELECT genre_name, titles FROM genre_by_country WHERE country_name = 'India'),
usa AS (SELECT genre_name, titles FROM genre_by_country WHERE country_name = 'United States')
SELECT
    COALESCE(i.genre_name, u.genre_name)  AS genre,
    COALESCE(i.titles, 0)                 AS india_titles,
    COALESCE(u.titles, 0)                 AS us_titles
FROM ind i
FULL OUTER JOIN usa u ON u.genre_name = i.genre_name
ORDER BY india_titles DESC, us_titles DESC
LIMIT 15;

/* ---------------------------------------------------------------------------
   J7. PEOPLE WHO BOTH ACTED AND DIRECTED.
   This is the query that justifies the whole schema design. Because
   dim_person is shared between the two role bridges, the question is a join
   on person_id. Against the flat table it is close to impossible: you would
   have to parse two comma-separated strings and compare their elements.
   RESULT: 484 people appear as both director and cast member.
--------------------------------------------------------------------------- */
SELECT
    p.person_name,
    COUNT(DISTINCT d.show_id) AS titles_directed,
    COUNT(DISTINCT a.show_id) AS titles_acted_in
FROM dim_person p
JOIN bridge_title_director d ON d.person_id = p.person_id
JOIN bridge_title_cast     a ON a.person_id = p.person_id
GROUP BY p.person_name
ORDER BY titles_directed DESC, titles_acted_in DESC
LIMIT 10;

-- J7B. How many such people are there in total?
SELECT COUNT(*) AS actor_directors
FROM (
    SELECT d.person_id
    FROM bridge_title_director d
    JOIN bridge_title_cast a ON a.person_id = d.person_id
    GROUP BY d.person_id
) s;                                                       -- 484

/* ---------------------------------------------------------------------------
   J8. SELF JOIN - most frequent co-production country pairs.
   The bridge is joined to itself on show_id. The predicate
   a.country_id < b.country_id does two jobs: it stops a country pairing with
   itself, and it keeps each pair once rather than twice (India-US and
   US-India are the same collaboration).
   RESULT: United States & United Kingdom lead, then United States & Canada.
--------------------------------------------------------------------------- */
SELECT
    c1.country_name            AS country_a,
    c2.country_name            AS country_b,
    COUNT(DISTINCT a.show_id)  AS co_productions
FROM bridge_title_country a
JOIN bridge_title_country b ON b.show_id = a.show_id
                            AND a.country_id < b.country_id
JOIN dim_country c1 ON c1.country_id = a.country_id
JOIN dim_country c2 ON c2.country_id = b.country_id
GROUP BY c1.country_name, c2.country_name
ORDER BY co_productions DESC
LIMIT 10;

/* ---------------------------------------------------------------------------
   J9. GENRE SHARE BY RELEASE COHORT - which genres grew as the catalogue
   modernised. Joins plus a window function partitioned by cohort, so each
   genre's share is computed within its own era.
   RESULT: International TV Shows and Documentaries gain share in the
   2018-2021 cohort; Independent Movies and Classic Movies lose it. This is
   the genre-level mechanism behind the 60/40 shift in Q1B.
--------------------------------------------------------------------------- */
WITH cohort_genre AS (
    SELECT
        CASE WHEN t.release_year >= 2018 THEN '2018-2021' ELSE 'pre-2018' END AS cohort,
        g.genre_name,
        COUNT(DISTINCT t.show_id) AS titles
    FROM dim_title t
    JOIN bridge_title_genre bg ON bg.show_id = t.show_id
    JOIN dim_genre g           ON g.genre_id = bg.genre_id
    GROUP BY 1, 2
)
SELECT
    genre_name,
    MAX(titles) FILTER (WHERE cohort = 'pre-2018')  AS pre_2018,
    MAX(titles) FILTER (WHERE cohort = '2018-2021') AS modern,
    ROUND(MAX(100.0 * share) FILTER (WHERE cohort = '2018-2021'), 2) AS modern_share_pct,
    ROUND(MAX(100.0 * share) FILTER (WHERE cohort = 'pre-2018'), 2)  AS pre_2018_share_pct
FROM (
    SELECT cohort, genre_name, titles,
           titles::numeric / SUM(titles) OVER (PARTITION BY cohort) AS share
    FROM cohort_genre
) s
GROUP BY genre_name
ORDER BY modern DESC NULLS LAST
LIMIT 12;

/* ---------------------------------------------------------------------------
   J10. AVERAGE RUNTIME BY GENRE (films only).
   duration_value is only comparable within one unit, so the type filter is
   mandatory. AVG ignores NULLs automatically.
   RESULT: Classic Movies and Dramas run longest; Stand-Up Comedy and
   Children & Family Movies shortest.
--------------------------------------------------------------------------- */
SELECT
    g.genre_name,
    COUNT(DISTINCT t.show_id)            AS movies,
    ROUND(AVG(t.duration_value), 1)      AS avg_minutes,
    MIN(t.duration_value)                AS shortest,
    MAX(t.duration_value)                AS longest
FROM dim_genre g
JOIN bridge_title_genre b ON b.genre_id = g.genre_id
JOIN dim_title t          ON t.show_id  = b.show_id
WHERE t.type = 'Movie' AND t.duration_value IS NOT NULL
GROUP BY g.genre_name
HAVING COUNT(DISTINCT t.show_id) >= 100
ORDER BY avg_minutes DESC;

/* ---------------------------------------------------------------------------
   J11. COUNTRY LEADERBOARD with format mix and acquisition lag.
   Three joins and four aggregates in one pass, the kind of summary a content
   team would actually want.
   RESULT: the US leads on volume; India is almost entirely film (92%);
   Japan and South Korea are series-heavy.
--------------------------------------------------------------------------- */
SELECT
    c.country_name,
    COUNT(DISTINCT t.show_id)                                        AS titles,
    ROUND(100.0 * COUNT(DISTINCT t.show_id) FILTER (WHERE t.type = 'Movie')
          / COUNT(DISTINCT t.show_id), 1)                            AS movie_pct,
    ROUND(AVG(t.year_added - t.release_year), 2)                     AS mean_lag_years
FROM dim_country c
JOIN bridge_title_country b ON b.country_id = c.country_id
JOIN dim_title t            ON t.show_id    = b.show_id
GROUP BY c.country_name
HAVING COUNT(DISTINCT t.show_id) >= 150
ORDER BY titles DESC;

/* ---------------------------------------------------------------------------
   J12. SEMI-JOIN with EXISTS - titles that are tagged International Movies
   but have no country recorded, an internal contradiction in the source data.
   EXISTS stops at the first match and never multiplies rows, which is why it
   is preferred over a JOIN when you only need existence, not columns.
   RESULT: 209 titles are tagged International Movies yet have no country
   recorded. The genre tag and the country field are therefore populated
   independently, so neither can be used to repair the other - a concrete
   limit on how far this dataset can be cleaned.
--------------------------------------------------------------------------- */
SELECT COUNT(*) AS international_but_no_country
FROM dim_title t
WHERE EXISTS (
        SELECT 1
        FROM bridge_title_genre bg
        JOIN dim_genre g ON g.genre_id = bg.genre_id
        WHERE bg.show_id = t.show_id
          AND g.genre_name = 'International Movies'
      )
  AND NOT EXISTS (
        SELECT 1 FROM bridge_title_country bc WHERE bc.show_id = t.show_id
      );

-- End of file 05
