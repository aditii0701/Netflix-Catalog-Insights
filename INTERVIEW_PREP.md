# Interview Defence: Netflix Catalog Insights

**Do not upload this file to GitHub.** It is your preparation material.

---

## Part 1 — The three things to get right before anything else

### 1.1 The 60/40 figure: how to handle it

This is the only claim on your CV that is not literally true of the whole dataset. The catalogue is 69.6% film / 30.4% series. Your repo now contains a query (Q1B) where 60/40 is genuinely correct: titles **released** from 2018 onward split 58.9% film / 41.1% series.

**If they raise it, lead with the true number. Never defend 60/40 as the overall split.**

> "The catalogue overall is about 70/30, 6,131 films to 2,676 series. The 60/40 is the modern cohort — titles released 2018 onward, which comes out at 58.9/41.1. That's the finding I was pointing at, because the aggregate is dominated by an older licensed film back-catalogue and it hides the actual direction of travel. Film share drops from 79% in 2010 to 47% in 2021, which is the first year series outnumber films. The bullet is compressed and I'd write it more precisely now."

Three rules for this moment:
- **Concede the imprecision immediately.** "The bullet is compressed" costs you nothing. Arguing costs you the interview.
- **Then give the real analysis**, which is genuinely more interesting than the number they caught.
- **Do not say "typo"** if they haven't accused you of anything. If they simply ask "tell me about the 60/40", answer with the cohort framing and move on.

### 1.2 Provenance: say it before they find it

The original 15 questions come from a published guided exercise. Interviewers in data roles have seen it. Your README now states this in the first section, which means you get credit for candour instead of being caught.

> "I learned SQL by working through a published set of Netflix business questions. Then I extended it, and the extension is the actual project: I profiled the data, found four defects the exercise didn't handle, built a cleaning layer with constraints, normalised the flat table into a joinable schema, fixed five bugs in the original queries, added twelve relational queries, and wrote a validation suite."

Never say "I designed this from scratch." If they find the source after you've claimed originality, everything else you say becomes suspect.

### 1.3 "Joins" and "cleaning" are now true

They weren't before. `03_normalized_schema.sql` and `05_analysis_joins.sql` give you INNER, LEFT, FULL OUTER, self and anti joins. `02_cleaning.sql` covers all 12 fields with enforced constraints. If asked to show either, you have a file to open.

---

## Part 2 — Your pitch

### 60-second version

> "Single-table exploratory analysis of Netflix's public catalogue: 8,807 titles, 12 fields, PostgreSQL. The structural problem is that four columns — country, genre, cast, director — pack multiple values into one cell as comma-separated text, and duration mixes minutes and seasons in a single column. So almost the whole project is about making the data answerable before answering anything.
>
> I built it as four layers: a raw staging load that keeps the defects visible, a cleaning layer with database constraints, a normalised schema with bridge tables, and then the analysis, 30 queries in total. The headline finding is that the catalogue is 70% film overall, but restricted to titles released since 2018 it's 59/41, and 2021 is the first year series outnumber films. Films sit in the catalogue with a median two-year lag from release; series arrive the same year. So the aggregate describes a licensed film library while the recent cohort shows what Netflix is actually commissioning.
>
> The thing I'd flag as a limitation is that 30% of titles have no director, and 93% of those are series, because series are credited to creators. So it's structural missingness, not random, and director analysis in this dataset is effectively film-only."

### The 2-minute version adds

- **The normalisation payoff:** `country = 'India'` returns 972 titles; expanding the multi-value column returns 1,046. A 7.6% undercount hiding in an exact-match filter.
- **The genre taxonomy finding:** all 42 genre tags are 100% film or 100% series, never mixed. "Dramas" is film-only and pairs with "TV Dramas". So a naive "most popular genre" ranking is two separate rankings stacked together.
- **The reproducibility layer:** 22 assertions that print PASS or FAIL, so the documented numbers are testable rather than asserted.

---

## Part 3 — Bullet-by-bullet defence

### Bullet 1: "Derived insights on 60% movies vs 40% TV shows, publishing the results with 100% query reproducibility and GitHub record."

| Claim | Where it lives | What to say |
|---|---|---|
| 60/40 | `04_analysis_core.sql` Q1B; README finding 1 | Modern cohort, release_year ≥ 2018, 58.9/41.1. See 1.1 above. |
| 100% query reproducibility | `06_validation.sql`, 22 assertions | "Reproducible is a claim, so I wrote the test. Drop the database, re-run the six files, and 22 of 22 checks print PASS. Every number in RESULTS.md is asserted against the live database. The reason it mattered here is that the original queries used CURRENT_DATE for 'last 5 years' logic, which silently returns different answers every year — today it returns zero rows, because the data stops in 2021. I anchored everything on MAX(date_added) instead." |
| GitHub record | the repo | Six numbered files, run in order, one command each. |

**The strongest thing you can say on this bullet** is the `CURRENT_DATE` fix. It's a real reproducibility bug, you found it, and the fix is the kind of thing that separates someone who has thought about pipelines from someone who has only written queries.

### Bullet 2: "Built 15+ SQL queries (joins, aggregation functions) to identify top 5 genres, 20+ prolific directors and yearly content trends."

| Claim | Where it lives | Numbers |
|---|---|---|
| 15+ queries | 18 in file 04, 12 in file 05 = **30** | — |
| joins | `05_analysis_joins.sql` | INNER, LEFT, FULL OUTER, self, anti, semi (EXISTS) |
| aggregation functions | throughout | COUNT, SUM, AVG, MIN, MAX, ROUND, STRING_AGG, PERCENTILE_CONT, FILTER |
| top 5 genres | Q9, J1 | International Movies 2,752 · Dramas 2,427 · Comedies 1,674 · International TV Shows 1,351 · Documentaries 869 |
| 20+ prolific directors | Q16, J2 | Top 20 table, Rajiv Chilaka 22 down to 8 at rank 20. Of 4,993 directors, 119 have ≥5 titles, only 12 have ≥10. |
| yearly content trends | Q17, Q1C, J9 | Additions peak 2019 at 2,016; film share falls 79.4% (2010) → 46.8% (2021) |

**If asked why you'd need joins at all on a single-table dataset**, that is the best question you could get:

> "You don't, against the flat file, and that's the problem. The flat table can't answer relational questions. 'Which people both directed and acted' is close to impossible against two comma-separated strings, but once there's a shared person dimension and two role bridges, it's a join on person_id — 484 people. Same with co-production pairs, which needs a self-join on the country bridge. So I normalised it, and then the joins aren't decoration, they're what makes those questions answerable."

### Bullet 3: "Analyzed 8,800+ records from the Netflix dataset for cleaning and structuring data across 10+ fields to ensure its accuracy."

| Claim | Backing |
|---|---|
| 8,800+ records | 8,807 exactly, asserted by check 1 |
| cleaning and structuring | `02_cleaning.sql`, all 12 fields, treatment table in README |
| 10+ fields | 12 source fields, expanded to 16 columns in `netflix_clean` |
| to ensure accuracy | 7 CHECK/PK constraints, 22 validation assertions |

Have the seven defects ready: the three shifted rows, the mixed-unit duration, the four multi-value columns, the stray leading delimiters, the free-text date, the UR/NR duplication, and the genre/country contradiction.

**The line that lands:** "No rows were deleted. 8,807 in, 8,807 out. I made missing values explicit as NULL rather than dropping them, because dropping the 2,634 director-less rows would have biased every other result in the project, and because 93% of them are series, so the drop wouldn't even have been random."

---

## Part 4 — Numbers to memorise

**Absolute minimum:** 8,807 rows · 12 fields · 6,131 films / 2,676 series = 69.6/30.4 · modern cohort 58.9/41.1 · 2,634 missing directors (29.9%) · 42 genre tags · 122 countries · snapshot 2021-09-25 · top genre International Movies 2,752 · top director Rajiv Chilaka 22 · additions peak 2019 at 2,016 · 972 → 1,046 India · 22/22 checks pass.

**Second tier:** nulls — country 831, cast 825, date_added 10, rating 4 (7 post-repair), duration 3 · top countries US 3,690 / India 1,046 / UK 806 · most common rating TV-MA (2,062 films, 1,145 series) · 99 series over 5 seasons · longest film Bandersnatch 312 min · 4,993 directors, 119 with ≥5, 12 with ≥10 · 484 actor-directors · acquisition lag median 2 years film / 0 series · 6,787 multi-genre titles, 1,320 multi-country.

**If you blank on a number:** "I'd have to check the exact figure, it's in RESULTS.md, but the order of magnitude is X and the direction is Y." Never invent a number. A guessed figure that contradicts your own repo is far worse than "let me check".

---

## Part 5 — SQL concept questions

**Why a window function for "most common rating per type"?**
GROUP BY gives counts per (type, rating), but SQL has no aggregate meaning "keep the top row per group". So: aggregate in a CTE, rank within each type with `RANK() OVER (PARTITION BY type ORDER BY count DESC)`, filter `rank = 1` in an outer query. PARTITION BY restarts the numbering per type. This is the top-N-per-group pattern.

**Why RANK and not ROW_NUMBER or DENSE_RANK?**
ROW_NUMBER always produces unique numbers, so on a tie it picks one row arbitrarily and silently drops a joint winner. RANK gives both rows rank 1. DENSE_RANK differs from RANK only in what follows a tie — RANK skips (1,1,3), DENSE_RANK doesn't (1,1,2) — so for a `= 1` filter they're identical, but ROW_NUMBER genuinely isn't.

**Can you filter on a window function in WHERE?**
No. Logical order is FROM → WHERE → GROUP BY → HAVING → SELECT (window functions here) → ORDER BY → LIMIT. Window functions are evaluated after WHERE, so you must wrap them in a CTE or subquery. This is exactly why Q2 has an outer query.

**WHERE vs HAVING?**
WHERE filters rows before grouping; HAVING filters groups after aggregating. In J4 the "at least 5 titles" threshold must be HAVING, because the count doesn't exist until after the GROUP BY.

**CTE vs subquery?**
Readability and reuse; a CTE names each logical step. Performance: in Postgres 12+ CTEs are inlined by default so there's usually no difference; before 12 they were an optimisation fence, always materialised. `WITH ... MATERIALIZED` forces the old behaviour if you want it.

**COUNT(*) vs COUNT(col) vs COUNT(DISTINCT col)?**
COUNT(*) counts rows. COUNT(col) skips NULLs. In this project COUNT(*) = 8,807 and COUNT(director) = 6,173, and that gap is the finding. COUNT(DISTINCT show_id) is mandatory after a bridge join, because the join multiplies rows.

**What's the fan-out problem?**
`bridge_title_genre` has 19,323 rows against 8,807 titles, because a title with three tags contributes three rows. So after joining, COUNT(*) counts pairings, not titles, and any SUM of a title-level measure is inflated. It fails silently rather than erroring, which is what makes it dangerous. Every count in file 05 uses COUNT(DISTINCT show_id).

**Explain the join types you used.**
- INNER: rows matching on both sides (J1, genre to title).
- LEFT: all left rows, NULLs where no match (J5).
- ANTI-JOIN: LEFT JOIN then `WHERE right_key IS NULL` — returns exactly the non-matching rows. 2,634 titles with no director (J5).
- SELF: a table joined to itself. Co-production pairs (J8), with `a.country_id < b.country_id` to stop self-pairing and to keep each pair once rather than twice.
- FULL OUTER: all rows from both sides. Needed in J6 because some genres exist in India and not the US; INNER would silently drop exactly the interesting rows.
- SEMI-JOIN via EXISTS (J12): stops at the first match, never multiplies rows, so it's preferred over a join when you only need existence.

**Why EXISTS rather than IN?**
EXISTS short-circuits on the first match and handles NULLs safely. `NOT IN` against a subquery containing a NULL returns no rows at all, because `x NOT IN (1, NULL)` evaluates to UNKNOWN. `NOT EXISTS` has no such trap.

**What does UNNEST(STRING_TO_ARRAY(col, ',')) do?**
STRING_TO_ARRAY splits 'India, US' into the array `{India," US"}`; UNNEST expands the array to one row per element. TRIM is mandatory — without it ' Dramas' and 'Dramas' count as two genres and every genre total fragments silently. `CROSS JOIN LATERAL` lets the expansion reference the row it came from.

**Why normalise, and to what?**
The flat table violates 1NF: four columns hold repeating groups. I decomposed each into a dimension plus a bridge with a composite primary key, which is the standard many-to-many pattern. dim_person is shared between the director and cast bridges, so a person exists once and the bridge defines the role — that single choice is what makes "who both acted and directed" a two-line join. Benefits: no runtime parsing, indexable lookups, referential integrity, and relational questions become expressible.

**What indexes did you add and why?**
The composite PK on each bridge already indexes (show_id, dim_id), which serves "genres for this title". I added an index on the trailing column (genre_id, country_id, person_id) for the reverse lookup, "all titles for this genre". Plus type, release_year and year_added on the clean table, since nearly every query filters on those.

**How would you check whether an index is being used?**
`EXPLAIN ANALYZE` and look for an Index Scan or Bitmap Index Scan rather than a Seq Scan. Honest caveat worth saying: at 8,807 rows Postgres will often choose a sequential scan anyway, because the table fits in a handful of pages and the planner is right to. The indexes are about the pattern being correct at scale, not about measurable gains here.

---

## Part 6 — Project-specific questions

**What was the hardest part?**
The multi-value columns, because they're wrong in a way that doesn't announce itself. `GROUP BY country` runs fine and returns a clean-looking result where 'India, United States' is its own category. Nothing errors. I only caught it by sanity-checking India's count two ways and getting 972 versus 1,046.

**What would you do differently?**
Profile before writing a single analytical query. I wrote queries first and kept discovering defects — like the three rows with duration in the rating column — that invalidated results I'd already produced. The staging-plus-profile layer in file 01 is the fix, but I built it after learning why I needed it.

**What surprised you?**
That all 42 genre tags are format-exclusive. I expected "Dramas" to span films and series, and went looking for the movie/TV split within each genre. Every tag came back 100% or 0%. The taxonomy is partitioned by format, with tag pairs like Dramas / TV Dramas. It reframed the genre analysis: I'd been treating one ranking as comparable across formats when it's really two rankings stacked.

**What business decision could this inform?**
Carefully, and with limits. The mix shift and the acquisition-lag gap say something real about commissioning versus licensing. But this is a catalogue snapshot: it records availability, not viewing. There are no watch hours, no engagement, no cost. So it can inform questions about catalogue composition and supply, and it cannot answer anything about what audiences actually watch. I'd want viewing and cost data before recommending a commissioning decision.

**How would you extend it?**
Join to IMDb or TMDB for ratings and budget, so the catalogue can be evaluated on quality rather than just counted. Add a region dimension, since production country isn't availability region and Netflix licensing is regional. Take snapshots over time to measure removals, which this dataset can't see at all. And move the pipeline into dbt with tests, since files 01–03 are already a staging-then-marts pattern in all but name.

**Why Postgres?**
The multi-value problem needs array functions, and STRING_TO_ARRAY, UNNEST and LATERAL are clean in Postgres. Window functions and FILTER are well supported. It's also free and the whole thing reproduces on a laptop. If I were rebuilding for scale I'd reach for the same SQL on BigQuery or Snowflake with minor dialect changes.

**Is this dataset trustworthy?**
Only partly, and I'd say so before drawing conclusions. It's a community Kaggle export, not a Netflix system of record, so field accuracy can't be verified independently. J12 shows an internal contradiction: 209 titles are tagged International Movies with no country recorded, which means those two fields are populated independently and neither can repair the other. That's a hard ceiling on how clean it can get.

**Why keep the naive keyword query if you know it's flawed?**
Because the gap is the finding. Naive substring matching flags 342 titles; word-boundary matching flags 217. So 37% of the naive matches are false positives like "skill" and "killer whale". Keeping both quantifies the error rather than hiding it. I'd also push back on the question itself — descriptions are marketing copy, and the rating field is the purpose-built signal for content sensitivity.

---

## Part 7 — Live SQL they may ask you to write

Practise these until they're automatic. They're the natural asks off this project.

1. **Second-most-common rating per type.** Same CTE as Q2, filter `rnk = 2`. Mention DENSE_RANK if they care about ties.
2. **Titles in a genre but not another.** Anti-join or `NOT EXISTS` on the genre bridge.
3. **Running total of additions by year.** `SUM(COUNT(*)) OVER (ORDER BY year_added)`.
4. **Year-on-year growth.** `LAG(...) OVER (ORDER BY year)`, and wrap the denominator in `NULLIF(..., 0)` to avoid division by zero.
5. **Top 3 genres per country.** `ROW_NUMBER() OVER (PARTITION BY country ORDER BY titles DESC)`, filter ≤ 3.
6. **Directors whose every title is a film.** `HAVING COUNT(*) = COUNT(*) FILTER (WHERE type = 'Movie')`.
7. **Median runtime.** `PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY duration_value)`.
8. **Split a comma-separated column.** `CROSS JOIN LATERAL UNNEST(STRING_TO_ARRAY(col, ','))`, and say TRIM out loud.
9. **Find duplicates.** `GROUP BY key HAVING COUNT(*) > 1`.
10. **Titles with no genre.** Anti-join against the bridge.

---

## Part 8 — Traps and how to handle them

| Trap | Response |
|---|---|
| "Your CV says 60/40 but I get 70/30." | Concede the phrasing, give the cohort analysis. See 1.1. Do not argue. |
| "This looks like a tutorial project." | "It started as one. Here's what I added." Then the provenance script. |
| "Where are the joins?" | Open `05_analysis_joins.sql`. Explain why the flat table needed normalising first. |
| "Show me the cleaning." | Open `02_cleaning.sql`. Lead with the three shifted rows — it's concrete and it's yours. |
| "This is just SELECT and GROUP BY." | Agree partly, then point at the design: staging/clean/normalised layering, constraints, the fan-out rule, the validation suite. The value isn't query exotica. |
| "What's the business impact?" | Don't overclaim. Availability data, not viewing data. Say what it can and can't support. |
| A number you don't remember. | "It's in RESULTS.md — order of magnitude X, direction Y." Never guess. |
| "Did you use AI for this?" | Be straightforward. You learned from a guided exercise, used tooling, and can explain every line — which is the part that matters. Then invite them to pick any query and walk through it. That offer only works if it's true, so make sure it is. |

---

## Part 9 — Before you walk in

- [ ] Re-run all six files on a clean database. See 22/22 PASS with your own eyes.
- [ ] Open every file once and read your own comments. You wrote the reasoning down; know where it is.
- [ ] Be able to explain Q2 (CTE + RANK), J5 (anti-join) and J8 (self-join) line by line. Those three cover most of what gets probed.
- [ ] Say the 60-second pitch out loud five times. Out loud, not in your head.
- [ ] Rehearse the 60/40 concession until it sounds relaxed rather than defensive.
- [ ] Commit the files in separate commits with real messages, not one bulk upload.

## Part 10 — Questions to ask them

- How normalised is the data you work with day to day, and how much time goes on cleaning before analysis?
- Do you use a transformation layer like dbt, or is it mostly queries against the warehouse?
- How do you handle reproducibility — are documented numbers tested anywhere, or is it convention?
- What does the path from analyst to senior analyst look like on your team?
