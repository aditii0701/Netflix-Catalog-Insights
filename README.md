# Netflix Catalog Insights Using SQL

Exploratory and relational analysis of Netflix's public title catalogue (8,807 titles, 12 fields) in PostgreSQL 16. The project covers raw ingestion, a documented cleaning layer, normalisation from a flat file into a joinable schema, 30 analytical queries, and an automated validation suite that reproduces every published number.

**Stack:** PostgreSQL 16 · psql · no external dependencies

---

## Provenance

I started this as a guided practice project, working through a published set of 15 Netflix business questions to learn SQL properly. The original exercise ran those queries against a single flat table.

I then took it further on my own, and that extension is the substance of this repository:

- Profiled the source data and found four defects the original exercise did not address, including three rows where the duration value was stored in the rating column.
- Built a cleaning layer (`02_cleaning.sql`) covering all 12 source fields, with database constraints that make the defects unable to return.
- Normalised the flat table into a 1NF schema of four dimension tables and four bridge tables (`03_normalized_schema.sql`), which revealed a 7.6% undercount of Indian titles caused by exact-match filtering on a multi-value column.
- Found and fixed five bugs in the original queries, each documented inline at the query it affects.
- Added 12 relational queries (`05_analysis_joins.sql`) that the flat table cannot answer at all, plus a cohort analysis that surfaced the project's headline finding.
- Wrote a 22-check validation suite (`06_validation.sql`) so the results are verifiable rather than merely claimed.

---

## Headline findings

**1. The catalogue as a whole is 69.6% film, but that figure hides the strategy.**
Overall the catalogue holds 6,131 films and 2,676 series. Restricted to titles *released* in the final four years of the snapshot (2018–2021), the mix narrows to **58.9% film / 41.1% series — roughly 60/40**. Year by year the film share falls from 79.4% (2010) to 61.5% (2019), 54.2% (2020) and 46.8% (2021), the first year series outnumber films. The aggregate is dominated by an older licensed film back-catalogue; the recent cohort is where the commissioning strategy is visible.

**2. Films are licensed, series are acquired fresh.**
Median gap between release year and catalogue addition is 2 years for films and 0 for series. 67.4% of series arrive within a year of release, against 49.6% of films. This is the mechanism behind finding 1.

**3. The genre taxonomy is format-partitioned, which invalidates naive genre rankings.**
Every one of the 42 genre tags is either 100% film or 100% series. "Dramas" is film-only and pairs with "TV Dramas"; "Comedies" pairs with "TV Comedies"; "Documentaries" pairs with "Docuseries". International Movies (2,752) outranking International TV Shows (1,351) is not one genre being twice as popular, it is two separate rankings stacked together.

**4. Missing director data is structural, not random.**
2,634 titles (29.9%) have no director, and 2,446 of them (92.9%) are series, which are credited to creators rather than directors. Director-level analysis in this dataset is therefore effectively film-only. Treating the gap as random missingness would be wrong.

**5. Normalisation changes the answers.**
Filtering `country = 'India'` returns 972 titles. Expanding the multi-value column returns 1,046, recovering 74 co-productions, a 7.6% undercount. 1,320 titles list more than one country and 6,787 list more than one genre, so this affects every geographic and genre result in the project.

---

## Pipeline

| File | Purpose | Output |
|---|---|---|
| `01_schema_staging.sql` | Raw load, all columns TEXT, plus a data profile that quantifies every defect before anything is changed | `netflix_raw` (8,807 rows) |
| `02_cleaning.sql` | Cleaning and structuring across all 12 fields, with CHECK constraints and a PRIMARY KEY | `netflix_clean` (8,807 rows, 16 cols) |
| `03_normalized_schema.sql` | Normalisation to 1NF: 4 dimensions, 4 bridge tables, foreign keys, indexes | 8 tables |
| `04_analysis_core.sql` | 18 analytical queries against the cleaned flat table | — |
| `05_analysis_joins.sql` | 12 relational queries against the normalised schema | — |
| `06_validation.sql` | 22 PASS/FAIL assertions covering load, cleaning, ETL and findings | test report |
| `RESULTS.md` | Every documented output value | — |

Run in order:

```bash
createdb netflix_db
psql -d netflix_db -f 01_schema_staging.sql      # run from the repo root; \copy reads netflix_titles.csv
psql -d netflix_db -f 02_cleaning.sql
psql -d netflix_db -f 03_normalized_schema.sql
psql -d netflix_db -f 04_analysis_core.sql
psql -d netflix_db -f 05_analysis_joins.sql
psql -d netflix_db -f 06_validation.sql          # expect 22 PASS, 0 FAIL
```

Verified on a clean database: dropping `netflix_db` and re-running the six files in order reproduces all 22 checks as PASS.

---

## Data quality: defects found and how each was handled

| # | Defect | Extent | Treatment |
|---|---|---|---|
| 1 | Duration value stored in the `rating` column | 3 rows (`s5542`, `s5795`, `s5814`) | Detected by pattern rather than hard-coded ID, value moved to `duration`, rating set to NULL rather than guessed |
| 2 | `duration` mixes two units in one column | 6,131 minutes, 2,676 seasons | Split into `duration_value INT` + `duration_unit`, with a CHECK constraint tying unit to content type |
| 3 | Four columns hold comma-separated repeating groups | 1,320 multi-country, 6,787 multi-genre titles | Normalised into bridge tables; delimiters standardised first |
| 4 | Stray leading delimiters producing empty tokens | 7 empty tokens (e.g. `s194`, `s366`) | Leading/trailing commas stripped before splitting, preventing a phantom `''` country |
| 5 | `date_added` stored as free text | all rows | Cast to DATE; the 10 rows with no value stay NULL |
| 6 | `UR` and `NR` both mean unrated | 2 labels, 1 category | Folded to `NR` so top-N rating queries do not split one group |
| 7 | Genre tag and country field contradict each other | 209 titles tagged International Movies with no country | Documented as a hard limit; neither field can be used to repair the other |

No rows were deleted at any stage. 8,807 in, 8,807 out. Missing values are made explicit as NULL rather than dropped, because dropping the 2,634 director-less rows would bias every other result.

---

## Bugs found in the original query set

| Query | Bug | Effect | Fix |
|---|---|---|---|
| Documentaries | `LIKE '%Documentaries'` with no trailing wildcard | Matched only rows where the tag happened to be last in the string | Exact match on the expanded array; 869 titles |
| Longest movie | No `LIMIT 1`, and `::INT` cast on a NULL duration | Returned all 6,131 films, and crashed on 3 rows | Pre-typed column, type filter, `LIMIT 1` |
| Last 5 years | Anchored on `CURRENT_DATE` | Returns 0 rows once the wall clock passes 2026 | Anchored on `MAX(date_added)`, the snapshot date |
| Top actors in India | `country = 'India'` exact match | Dropped 74 co-productions | Array expansion, consistent with the country query |
| India yearly | Column named `avg_release` | It computes a share, not an average | Renamed `pct_of_india_total` |
| Keyword categorisation | `ILIKE '%kill%'` | Matches "skill", "killer whale"; 125 of 342 matches are false positives | Word-boundary regex alongside, to quantify the error |

---

## Techniques used

Aggregation with `GROUP BY` and `HAVING` · conditional aggregation with `FILTER` · CTEs, including chained CTEs · window functions (`RANK`, `ROW_NUMBER`, `LAG`, `SUM() OVER`, `PERCENTILE_CONT`) · `CASE` expressions · scalar, correlated and `EXISTS` subqueries · `STRING_TO_ARRAY` + `UNNEST` with `CROSS JOIN LATERAL` · INNER, LEFT, FULL OUTER, self and anti joins · `STRING_AGG` · regex with `regexp_replace` and `~*` · primary, foreign and composite keys, CHECK constraints, indexes

---

## Known limitations

- The catalogue is a point-in-time snapshot ending 25 September 2021. It records what was available, not what was watched, so nothing here speaks to popularity or viewing hours.
- Removed titles are absent, so the catalogue cannot be treated as a complete history of what Netflix ever carried.
- `country` reflects production country, which is not the same as availability region; Netflix licensing is regional and this dataset has no region dimension.
- "International" is defined relative to a US viewer, which is why it is India's largest tag.
- 2021 is a partial year (ends 25 September), so its counts are not comparable to full years without annualising.
- Source is a public Kaggle export rather than a Netflix system of record, so field-level accuracy cannot be independently verified.

## Dataset

[Netflix Movies and TV Shows](https://www.kaggle.com/datasets/shivamb/netflix-shows) (Kaggle, public). `netflix_titles.csv` is committed so the pipeline is runnable as-is.
