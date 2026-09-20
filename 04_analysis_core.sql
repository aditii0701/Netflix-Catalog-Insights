/* ============================================================================
   FILE 04 - CORE ANALYSIS (18 queries)
   Engine  : PostgreSQL 16
   Run     : psql -d netflix_db -f 04_analysis_core.sql
   Input   : netflix_clean
   ----------------------------------------------------------------------------
   Techniques used in this file: aggregation with GROUP BY, conditional
   aggregation with FILTER, CTEs, window functions (RANK, LAG, SUM OVER),
   CASE expressions, scalar and correlated subqueries, array expansion with
   STRING_TO_ARRAY + UNNEST, and LATERAL joins.

   SNAPSHOT DATE
   The catalogue is frozen at 2021-09-25. Any query phrased as "the last N
   years" is therefore measured against that snapshot, not CURRENT_DATE.
   Using CURRENT_DATE returns zero rows today and would have silently returned
   different answers every year - the single worst reproducibility bug in the
   original query set.
============================================================================ */

/* ---------------------------------------------------------------------------
   Q1. CONTENT MIX - movies versus TV shows across the whole catalogue.
   Technique: GROUP BY with a window function used as the denominator.
   SUM(COUNT(*)) OVER () totals the grouped counts without a second pass or a
   subquery, which is the neat way to turn counts into shares.
   RESULT: Movie 6131 (69.6%), TV Show 2676 (30.4%)
--------------------------------------------------------------------------- */
SELECT
    type,
    COUNT(*)                                                      AS titles,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)            AS pct_of_catalogue
FROM netflix_clean
GROUP BY type
ORDER BY titles DESC;

/* ---------------------------------------------------------------------------
   Q1B. CONTENT MIX OF THE MODERN CATALOGUE (release_year >= 2018).
   Q1 describes the catalogue as a whole, which is dominated by an older film
   back-catalogue Netflix licensed in bulk. It hides the strategic shift.
   Restricting to titles released in the final four years of the snapshot
   (2018 to 2021) shows the mix converging to roughly 60/40.
   RESULT: Movie 2194 (58.9%), TV Show 1528 (41.1%)  ->  ~60/40
   This is the headline finding of the project, and Q1C shows why.
--------------------------------------------------------------------------- */
SELECT
    type,
    COUNT(*)                                                      AS titles,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)            AS pct_of_cohort
FROM netflix_clean
WHERE release_year >= 2018
GROUP BY type
ORDER BY titles DESC;

/* ---------------------------------------------------------------------------
   Q1C. WHY THE MIX MOVES - movie share by release year, with year-on-year
   change. Technique: conditional aggregation with FILTER, plus LAG to compare
   each year against the previous one.
   FILTER (WHERE ...) is the ANSI way to write a conditional count; the older
   equivalent is SUM(CASE WHEN ... THEN 1 ELSE 0 END).
   RESULT: movie share falls from 79.4% (2010) to 61.5% (2019), 54.2% (2020)
   and 46.8% (2021) - the first year TV shows outnumber films.
--------------------------------------------------------------------------- */
WITH by_year AS (
    SELECT
        release_year,
        COUNT(*)                                        AS total_titles,
        COUNT(*) FILTER (WHERE type = 'Movie')          AS movies,
        COUNT(*) FILTER (WHERE type = 'TV Show')        AS tv_shows
    FROM netflix_clean
    WHERE release_year BETWEEN 2010 AND 2021
    GROUP BY release_year
)
SELECT
    release_year,
    total_titles,
    movies,
    tv_shows,
    ROUND(100.0 * movies / total_titles, 1)                         AS movie_pct,
    ROUND(100.0 * movies / total_titles, 1)
      - LAG(ROUND(100.0 * movies / total_titles, 1)) OVER (ORDER BY release_year)
                                                                    AS movie_pct_change
FROM by_year
ORDER BY release_year;

/* ---------------------------------------------------------------------------
   Q2. MOST COMMON RATING PER CONTENT TYPE.
   Technique: two chained CTEs and a window function.
   Why it needs a window function: a plain GROUP BY can give counts per
   (type, rating) but SQL has no aggregate meaning "keep the top row per
   group". So we aggregate first, rank within each type, then filter rank = 1.
   Why RANK and not ROW_NUMBER: on a tie ROW_NUMBER picks one row arbitrarily
   and silently discards a joint winner. RANK returns both.
   Why the filter is in an outer query: window functions are evaluated after
   WHERE, so you cannot write WHERE RANK() OVER (...) = 1.
   RESULT: TV-MA for both - 2062 movies, 1145 TV shows.
--------------------------------------------------------------------------- */
WITH rating_counts AS (
    SELECT type, rating, COUNT(*) AS rating_count
    FROM netflix_clean
    WHERE rating IS NOT NULL          -- exclude the 7 unrated rows explicitly
    GROUP BY type, rating
),
ranked AS (
    SELECT
        type, rating, rating_count,
        RANK() OVER (PARTITION BY type ORDER BY rating_count DESC) AS rnk
    FROM rating_counts
)
SELECT type, rating AS most_common_rating, rating_count
FROM ranked
WHERE rnk = 1
ORDER BY type;

/* ---------------------------------------------------------------------------
   Q3. TITLES RELEASED IN A GIVEN YEAR (2020), split by type.
   RESULT: 953 titles - 517 movies, 436 TV shows.
--------------------------------------------------------------------------- */
SELECT type, COUNT(*) AS titles
FROM netflix_clean
WHERE release_year = 2020
GROUP BY type
ORDER BY titles DESC;

/* ---------------------------------------------------------------------------
   Q4. TOP 5 PRODUCING COUNTRIES.
   Technique: array expansion. A co-production such as 'India, United States'
   must count once for each country, so the string is split and expanded
   before grouping. TRIM is essential; without it ' India' and 'India' become
   two separate countries.
   COUNT(DISTINCT show_id) rather than COUNT(*) guards against a title that
   lists the same country twice.
   RESULT: United States 3690, India 1046, United Kingdom 806, Canada 445,
           France 393
--------------------------------------------------------------------------- */
SELECT
    TRIM(c.val)                       AS country,
    COUNT(DISTINCT n.show_id)         AS titles
FROM netflix_clean n
CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(n.country, ',')) AS c(val)
WHERE TRIM(c.val) <> ''
GROUP BY TRIM(c.val)
ORDER BY titles DESC
LIMIT 5;

/* ---------------------------------------------------------------------------
   Q5. LONGEST MOVIE.
   Three fixes over the naive version: duration_value is already an integer so
   no fragile runtime cast is needed; the type filter keeps minutes and seasons
   from being compared; LIMIT 1 actually answers the question asked instead of
   returning all 6131 films in sorted order.
   RESULT: Black Mirror: Bandersnatch, 312 minutes.
--------------------------------------------------------------------------- */
SELECT title, release_year, duration_value AS minutes
FROM netflix_clean
WHERE type = 'Movie' AND duration_value IS NOT NULL
ORDER BY duration_value DESC
LIMIT 1;

/* ---------------------------------------------------------------------------
   Q6. CONTENT ADDED IN THE LAST 5 YEARS OF THE SNAPSHOT.
   The original used CURRENT_DATE, which today returns 0 rows because the data
   stops in 2021. Anchoring on MAX(date_added) makes the answer stable forever.
   RESULT: 8422 titles added between 2016-09-25 and 2021-09-25.
--------------------------------------------------------------------------- */
SELECT COUNT(*) AS titles_added_last_5y
FROM netflix_clean
WHERE date_added >= (SELECT MAX(date_added) FROM netflix_clean) - INTERVAL '5 years';

/* ---------------------------------------------------------------------------
   Q7. ALL TITLES BY A NAMED DIRECTOR ('Rajiv Chilaka').
   Expanding the director array and matching the trimmed element exactly is
   safer than LIKE '%Rajiv Chilaka%', which would also match a longer name
   that happens to contain this one as a substring.
   RESULT: 22 titles, the highest of any director in the catalogue.
--------------------------------------------------------------------------- */
SELECT n.show_id, n.title, n.type, n.release_year
FROM netflix_clean n
CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(n.director, ',')) AS d(val)
WHERE TRIM(d.val) = 'Rajiv Chilaka'
ORDER BY n.release_year;

/* ---------------------------------------------------------------------------
   Q8. TV SHOWS WITH MORE THAN 5 SEASONS.
   RESULT: 99 shows.
--------------------------------------------------------------------------- */
SELECT title, duration_value AS seasons, release_year
FROM netflix_clean
WHERE type = 'TV Show' AND duration_value > 5
ORDER BY seasons DESC, title;

/* ---------------------------------------------------------------------------
   Q9. TOP 5 GENRES, and the long tail behind them.
   42 distinct genre tags exist and 6787 of 8807 titles carry more than one,
   so these counts are tag counts and must not be summed to a title total.
   RESULT: International Movies 2752, Dramas 2427, Comedies 1674,
           International TV Shows 1351, Documentaries 869
--------------------------------------------------------------------------- */
SELECT
    TRIM(g.val)                                                   AS genre,
    COUNT(DISTINCT n.show_id)                                     AS titles,
    ROUND(100.0 * COUNT(DISTINCT n.show_id)
          / (SELECT COUNT(*) FROM netflix_clean), 1)              AS pct_of_catalogue
FROM netflix_clean n
CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(n.listed_in, ',')) AS g(val)
GROUP BY TRIM(g.val)
ORDER BY titles DESC
LIMIT 5;

-- Q9B. Full genre distribution, for the record: all 42 tags.
SELECT
    TRIM(g.val)               AS genre,
    COUNT(DISTINCT n.show_id) AS titles
FROM netflix_clean n
CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(n.listed_in, ',')) AS g(val)
GROUP BY TRIM(g.val)
ORDER BY titles DESC;

/* ---------------------------------------------------------------------------
   Q10. INDIA - top 5 release years by share of India's catalogue.
   The original named this column avg_release, but it computes each year's
   SHARE of India's total, which is a proportion and not an average. Renamed.
   It also used country = 'India', which drops the 74 co-productions; the
   array-expanded version below is the correct denominator (1046).
   RESULT: 2017 leads with 111 titles, 10.61% of India's catalogue.
--------------------------------------------------------------------------- */
WITH india AS (
    SELECT DISTINCT n.show_id, n.release_year
    FROM netflix_clean n
    CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(n.country, ',')) AS c(val)
    WHERE TRIM(c.val) = 'India'
)
SELECT
    release_year,
    COUNT(*)                                                      AS titles,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM india), 2)     AS pct_of_india_total
FROM india
GROUP BY release_year
ORDER BY titles DESC
LIMIT 5;

/* ---------------------------------------------------------------------------
   Q11. MOVIES TAGGED AS DOCUMENTARIES.
   The original wrote LIKE '%Documentaries' with no trailing wildcard, so it
   matched only rows where Documentaries happened to be the LAST tag in the
   string and silently dropped the rest. Exact matching on the expanded array
   fixes it and also avoids catching the separate tag 'Docuseries'.
   RESULT: all 869 Documentaries-tagged titles are movies. The TV equivalent
   is a separate tag, 'Docuseries' (395 titles), which is exactly why exact
   tag matching matters more than substring matching here.
--------------------------------------------------------------------------- */
SELECT COUNT(DISTINCT n.show_id) AS documentary_movies
FROM netflix_clean n
CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(n.listed_in, ',')) AS g(val)
WHERE TRIM(g.val) = 'Documentaries'
  AND n.type = 'Movie';

/* ---------------------------------------------------------------------------
   Q12. TITLES WITH NO DIRECTOR RECORDED.
   Not a curiosity - it is the completeness limit on every director-level
   conclusion in this project.
   RESULT: 2634 titles (29.9%), of which 2446 are TV shows. Series are
   credited to creators rather than directors, so the gap is structural
   rather than random. That distinction matters: it means director analysis
   is effectively film-only, not a random 70% sample.
--------------------------------------------------------------------------- */
SELECT
    type,
    COUNT(*)                                                  AS titles_without_director,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)        AS pct_of_missing
FROM netflix_clean
WHERE director IS NULL
GROUP BY type
ORDER BY titles_without_director DESC;

/* ---------------------------------------------------------------------------
   Q13. TITLES FEATURING A NAMED ACTOR ('Salman Khan') in the 10 years before
   the snapshot. Exact match on the expanded cast array, and the window is
   anchored to the snapshot year (2021) rather than CURRENT_DATE.
   RESULT: 3 titles (Paharganj 2019, Prem Ratan Dhan Payo 2015,
           Mumbai Cha Raja 2012).
--------------------------------------------------------------------------- */
SELECT n.title, n.type, n.release_year
FROM netflix_clean n
CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(n.casts, ',')) AS a(val)
WHERE TRIM(a.val) = 'Salman Khan'
  AND n.release_year > (SELECT EXTRACT(YEAR FROM MAX(date_added))::INT - 10 FROM netflix_clean)
ORDER BY n.release_year DESC;

/* ---------------------------------------------------------------------------
   Q14. TOP 10 ACTORS IN INDIAN-PRODUCED CONTENT.
   Both multi-value fields are expanded in the same query: country to identify
   Indian titles, cast to count appearances.
   RESULT: Anupam Kher 40, Shah Rukh Khan 34, Naseeruddin Shah 31,
           Akshay Kumar 29, Om Puri 29
--------------------------------------------------------------------------- */
SELECT
    TRIM(a.val)                 AS actor,
    COUNT(DISTINCT n.show_id)   AS titles
FROM netflix_clean n
CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(n.country, ',')) AS c(val)
CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(n.casts,   ',')) AS a(val)
WHERE TRIM(c.val) = 'India'
GROUP BY TRIM(a.val)
ORDER BY titles DESC
LIMIT 10;

/* ---------------------------------------------------------------------------
   Q15. KEYWORD CATEGORISATION of descriptions.
   Technique: CASE inside a subquery, then aggregate the derived label.
   CAVEAT, stated deliberately: ILIKE '%kill%' also matches 'skill' and
   'killer whale', and descriptions are marketing copy rather than content
   descriptions. The word-boundary version below (~*) is stricter, and the
   difference between the two is itself the finding: naive substring matching
   overstates the count. The rating field is the proper signal for this
   question; this query is a keyword exercise, not a content-safety measure.
   RESULT: naive 342 flagged, word-boundary 217 flagged. 125 of the 342
           matches, 37%, are false positives such as 'skill' and 'killer whale'.
--------------------------------------------------------------------------- */
SELECT
    CASE WHEN description ILIKE '%kill%' OR description ILIKE '%violence%'
         THEN 'Flagged' ELSE 'Not flagged' END                     AS naive_label,
    COUNT(*)                                                       AS titles
FROM netflix_clean
GROUP BY 1
ORDER BY titles DESC;

-- Q15B. Same question with word boundaries, to quantify the false positives.
SELECT
    COUNT(*) FILTER (WHERE description ILIKE '%kill%' OR description ILIKE '%violence%')
        AS naive_match,                                            -- 342
    COUNT(*) FILTER (WHERE description ~* '\y(kill|kills|killed|killing|violence|violent)\y')
        AS word_boundary_match                                     -- 282
FROM netflix_clean;

/* ---------------------------------------------------------------------------
   Q16. TOP 20 PROLIFIC DIRECTORS.
   4993 distinct directors appear in the catalogue. 119 have 5 or more titles
   and 12 have 10 or more, so "prolific" is a small group and worth bounding.
   RESULT: Rajiv Chilaka 22, Jan Suter 21, Raul Campos 19, Marcus Raboy 16,
           Suhas Kadav 16, Jay Karas 15, Cathy Garcia-Molina 13, down to
           8 titles at rank 20. Distribution: 3971 directors have 1 title,
           903 have 2-4, 107 have 5-9, only 12 have 10 or more.
--------------------------------------------------------------------------- */
SELECT
    TRIM(d.val)                                                        AS director,
    COUNT(DISTINCT n.show_id)                                          AS titles,
    COUNT(DISTINCT n.show_id) FILTER (WHERE n.type = 'Movie')          AS movies,
    COUNT(DISTINCT n.show_id) FILTER (WHERE n.type = 'TV Show')        AS tv_shows,
    MIN(n.release_year)                                                AS first_year,
    MAX(n.release_year)                                                AS last_year
FROM netflix_clean n
CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(n.director, ',')) AS d(val)
WHERE TRIM(d.val) <> ''
GROUP BY TRIM(d.val)
ORDER BY titles DESC, director
LIMIT 20;

-- Q16B. How concentrated is direction? Bucketed distribution.
SELECT
    CASE WHEN titles >= 10 THEN '10+ titles'
         WHEN titles >= 5  THEN '5-9 titles'
         WHEN titles >= 2  THEN '2-4 titles'
         ELSE '1 title' END                    AS bucket,
    COUNT(*)                                   AS directors
FROM (
    SELECT TRIM(d.val) AS director, COUNT(DISTINCT n.show_id) AS titles
    FROM netflix_clean n
    CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(n.director, ',')) AS d(val)
    WHERE TRIM(d.val) <> ''
    GROUP BY TRIM(d.val)
) s
GROUP BY 1
ORDER BY directors DESC;

/* ---------------------------------------------------------------------------
   Q17. YEARLY CONTENT TRENDS - catalogue additions per year with a running
   cumulative total and year-on-year growth.
   Technique: two window functions over the same ordered frame. SUM(...) OVER
   (ORDER BY ...) produces a running total; LAG reaches back one row for the
   growth calculation.
   RESULT: additions peak at 2016 titles in 2019, then fall to 1879 (2020) and
   1498 (2021, a partial year ending 25 September).
--------------------------------------------------------------------------- */
SELECT
    year_added,
    COUNT(*)                                                        AS titles_added,
    COUNT(*) FILTER (WHERE type = 'Movie')                          AS movies,
    COUNT(*) FILTER (WHERE type = 'TV Show')                        AS tv_shows,
    SUM(COUNT(*)) OVER (ORDER BY year_added)                        AS cumulative_titles,
    ROUND(100.0 * (COUNT(*) - LAG(COUNT(*)) OVER (ORDER BY year_added))
          / NULLIF(LAG(COUNT(*)) OVER (ORDER BY year_added), 0), 1) AS yoy_growth_pct
FROM netflix_clean
WHERE year_added IS NOT NULL
GROUP BY year_added
ORDER BY year_added;

/* ---------------------------------------------------------------------------
   Q18. ACQUISITION LAG - how long after release a title reaches the catalogue.
   Separates licensed back-catalogue (large lag) from originals and
   fresh acquisitions (lag near zero), which is the mechanism behind Q1B.
   RESULT: films have a mean lag of 5.73 years and a median of 2; series have
   a mean of 2.30 and a median of 0. 49.6% of films but 67.4% of series arrive
   within a year of release. Series are overwhelmingly fresh acquisitions and
   originals, films are largely licensed back-catalogue.
--------------------------------------------------------------------------- */
SELECT
    type,
    COUNT(*)                                                             AS titles,
    ROUND(AVG(year_added - release_year), 2)                             AS mean_lag_years,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY year_added - release_year)
                                                                         AS median_lag_years,
    ROUND(100.0 * COUNT(*) FILTER (WHERE year_added - release_year <= 1)
          / COUNT(*), 1)                                                 AS pct_within_1_year
FROM netflix_clean
WHERE year_added IS NOT NULL
GROUP BY type
ORDER BY titles DESC;

-- End of file 04
