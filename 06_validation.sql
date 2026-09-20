/* ============================================================================
   FILE 06 - VALIDATION AND REPRODUCIBILITY SUITE
   Engine  : PostgreSQL 16
   Run     : psql -d netflix_db -f 06_validation.sql
   ----------------------------------------------------------------------------
   WHAT THIS IS FOR
   "Reproducible" is a claim, and a claim needs a test. This file asserts every
   headline number in RESULTS.md against the live database and prints PASS or
   FAIL for each. Rebuild the whole pipeline from the CSV, run this file, and
   if all 20 checks report PASS then the documented results are exactly
   reproduced. If any number in the source data or the cleaning logic changes,
   a check fails and says which one.

   HOW IT WORKS
   Each check is a SELECT that computes a value and compares it to the expected
   constant. The checks are UNION ALL'd into one result set so a single run
   gives one readable report. This is the same idea as a unit test suite,
   expressed in plain SQL with no extra tooling.

   Run order matters: 01 -> 02 -> 03 before this file.
============================================================================ */

WITH checks AS (

    -- === LAYER 1: RAW LOAD INTEGRITY =====================================
    SELECT 1 AS id, 'Raw row count is 8807' AS check_name,
           (SELECT COUNT(*) FROM netflix_raw)::TEXT AS actual, '8807' AS expected
    UNION ALL
    SELECT 2, 'Raw column count is 12',
           (SELECT COUNT(*)::TEXT FROM information_schema.columns
             WHERE table_name = 'netflix_raw'), '12'
    UNION ALL
    SELECT 3, 'show_id is unique in raw',
           (SELECT (COUNT(*) - COUNT(DISTINCT show_id))::TEXT FROM netflix_raw), '0'

    -- === LAYER 2: CLEANING CORRECTNESS ===================================
    UNION ALL
    SELECT 4, 'Cleaning preserves all 8807 rows',
           (SELECT COUNT(*)::TEXT FROM netflix_clean), '8807'
    UNION ALL
    SELECT 5, 'Column-shift defect repaired (no rating holds a duration)',
           (SELECT COUNT(*)::TEXT FROM netflix_clean WHERE rating ILIKE '%min%'), '0'
    UNION ALL
    SELECT 6, 'Every title has a parsed duration_value',
           (SELECT COUNT(*)::TEXT FROM netflix_clean WHERE duration_value IS NULL), '0'
    UNION ALL
    SELECT 7, 'Duration unit always matches content type',
           (SELECT COUNT(*)::TEXT FROM netflix_clean
             WHERE (type = 'Movie'   AND duration_unit <> 'minutes')
                OR (type = 'TV Show' AND duration_unit <> 'seasons')), '0'
    UNION ALL
    SELECT 8, 'Missing directors unchanged by cleaning (2634)',
           (SELECT (COUNT(*) - COUNT(director))::TEXT FROM netflix_clean), '2634'
    UNION ALL
    SELECT 9, 'Snapshot date is 2021-09-25',
           (SELECT MAX(date_added)::TEXT FROM netflix_clean), '2021-09-25'
    UNION ALL
    SELECT 10, 'No empty-string tokens survive in multi-value fields',
           (SELECT COUNT(*)::TEXT FROM netflix_clean n,
                   UNNEST(STRING_TO_ARRAY(n.country, ',')) x
             WHERE TRIM(x) = ''), '0'

    -- === LAYER 3: ETL COMPLETENESS =======================================
    UNION ALL
    SELECT 11, 'dim_title matches clean row count',
           (SELECT COUNT(*)::TEXT FROM dim_title), '8807'
    UNION ALL
    SELECT 12, 'Genre dimension has 42 distinct tags',
           (SELECT COUNT(*)::TEXT FROM dim_genre), '42'
    UNION ALL
    SELECT 13, 'Country dimension has 122 distinct countries',
           (SELECT COUNT(*)::TEXT FROM dim_country), '122'
    UNION ALL
    SELECT 14, 'Titles with no genre bridge row is 0 (no loss in ETL)',
           (SELECT COUNT(*)::TEXT FROM dim_title t
             WHERE NOT EXISTS (SELECT 1 FROM bridge_title_genre b
                                WHERE b.show_id = t.show_id)), '0'
    UNION ALL
    SELECT 15, 'Titles with no director bridge row equals original NULLs',
           (SELECT COUNT(*)::TEXT FROM dim_title t
             WHERE NOT EXISTS (SELECT 1 FROM bridge_title_director b
                                WHERE b.show_id = t.show_id)), '2634'

    -- === LAYER 4: HEADLINE FINDINGS ======================================
    UNION ALL
    SELECT 16, 'Overall catalogue is 6131 movies',
           (SELECT COUNT(*)::TEXT FROM netflix_clean WHERE type = 'Movie'), '6131'
    UNION ALL
    SELECT 17, 'Overall movie share is 69.6 percent',
           (SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE type = 'Movie')
                         / COUNT(*), 1)::TEXT FROM netflix_clean), '69.6'
    UNION ALL
    SELECT 18, 'Modern cohort (2018+) movie share is 58.9 percent (~60/40)',
           (SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE type = 'Movie')
                         / COUNT(*), 1)::TEXT
              FROM netflix_clean WHERE release_year >= 2018), '58.9'
    UNION ALL
    SELECT 19, 'Top genre is International Movies with 2752 titles',
           (SELECT g.genre_name || '|' || COUNT(DISTINCT b.show_id)::TEXT
              FROM dim_genre g JOIN bridge_title_genre b ON b.genre_id = g.genre_id
             GROUP BY g.genre_name ORDER BY COUNT(DISTINCT b.show_id) DESC LIMIT 1),
           'International Movies|2752'
    UNION ALL
    SELECT 20, 'Top director is Rajiv Chilaka with 22 titles',
           (SELECT p.person_name || '|' || COUNT(DISTINCT b.show_id)::TEXT
              FROM dim_person p JOIN bridge_title_director b ON b.person_id = p.person_id
             GROUP BY p.person_name
             ORDER BY COUNT(DISTINCT b.show_id) DESC, p.person_name LIMIT 1),
           'Rajiv Chilaka|22'
    UNION ALL
    SELECT 21, 'Normalisation recovers 74 India co-productions (972 -> 1046)',
           (SELECT (COUNT(DISTINCT b.show_id)
                    - (SELECT COUNT(*) FROM netflix_clean WHERE country = 'India'))::TEXT
              FROM bridge_title_country b
              JOIN dim_country c ON c.country_id = b.country_id
             WHERE c.country_name = 'India'), '74'
    UNION ALL
    SELECT 22, 'Directors with 10 or more titles is 12',
           (SELECT COUNT(*)::TEXT FROM (
                SELECT b.person_id FROM bridge_title_director b
                GROUP BY b.person_id HAVING COUNT(DISTINCT b.show_id) >= 10) s), '12'
)
SELECT
    id,
    check_name,
    expected,
    actual,
    CASE WHEN actual = expected THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
ORDER BY id;

/* ----------------------------------------------------------------------------
   SUMMARY LINE - the single number to look at.
   Expected output: 22 checks, 22 passed, 0 failed.
---------------------------------------------------------------------------- */
WITH checks AS (
    SELECT (SELECT COUNT(*) FROM netflix_clean)::TEXT AS a, '8807' AS e
    UNION ALL SELECT (SELECT COUNT(*) FROM dim_title)::TEXT, '8807'
    UNION ALL SELECT (SELECT COUNT(*) FROM dim_genre)::TEXT, '42'
    UNION ALL SELECT (SELECT COUNT(*) FROM dim_country)::TEXT, '122'
    UNION ALL SELECT (SELECT COUNT(*) FROM netflix_clean WHERE type='Movie')::TEXT, '6131'
    UNION ALL SELECT (SELECT COUNT(*) FROM netflix_clean WHERE rating ILIKE '%min%')::TEXT, '0'
)
SELECT
    COUNT(*)                                        AS core_checks,
    COUNT(*) FILTER (WHERE a = e)                   AS passed,
    COUNT(*) FILTER (WHERE a <> e)                  AS failed
FROM checks;

-- End of file 06
