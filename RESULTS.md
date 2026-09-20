# Results

Every figure below was produced by the committed SQL against `netflix_titles.csv` on PostgreSQL 16, and is asserted by `06_validation.sql`. Rebuilding the database from scratch and re-running files 01–06 reproduces all of it, with 22 of 22 checks passing.

**Snapshot boundary:** the catalogue runs from 2008-01-01 to 2021-09-25. All "last N years" logic is measured from 2021-09-25, never from `CURRENT_DATE`.

---

## Dataset profile

| Metric | Value |
|---|---|
| Rows | 8,807 |
| Columns | 12 |
| Duplicate `show_id` | 0 |
| Duplicate title + type | 0 |
| Date range (`date_added`) | 2008-01-01 to 2021-09-25 |
| Release year range | 1925 to 2021 |

### Missingness by field

| Field | Missing | % |
|---|---|---|
| `director` | 2,634 | 29.9% |
| `country` | 831 | 9.4% |
| `cast` | 825 | 9.4% |
| `date_added` | 10 | 0.1% |
| `rating` | 4 (7 after repairing 3 shifted rows) | 0.1% |
| `duration` | 3 | 0.03% |
| `show_id`, `type`, `title`, `release_year`, `listed_in`, `description` | 0 | 0% |

### Multi-value fields

| Field | Titles with more than one value |
|---|---|
| `cast` | 7,101 |
| `listed_in` | 6,787 |
| `country` | 1,320 |
| `director` | 614 |

---

## Q1 — Content mix, whole catalogue

| Type | Titles | Share |
|---|---|---|
| Movie | 6,131 | 69.6% |
| TV Show | 2,676 | 30.4% |

## Q1B — Content mix, modern cohort (release_year ≥ 2018)

| Type | Titles | Share |
|---|---|---|
| Movie | 2,194 | **58.9%** |
| TV Show | 1,528 | **41.1%** |

Approximately **60/40**. This is the project's headline finding.

## Q1C — Movie share by release year

| Year | Titles | Movies | TV | Movie % | YoY change |
|---|---|---|---|---|---|
| 2010 | 194 | 154 | 40 | 79.4% | — |
| 2011 | 185 | 145 | 40 | 78.4% | −1.0 |
| 2012 | 237 | 173 | 64 | 73.0% | −5.4 |
| 2013 | 288 | 225 | 63 | 78.1% | +5.1 |
| 2014 | 352 | 264 | 88 | 75.0% | −3.1 |
| 2015 | 560 | 398 | 162 | 71.1% | −3.9 |
| 2016 | 902 | 658 | 244 | 72.9% | +1.8 |
| 2017 | 1,032 | 767 | 265 | 74.3% | +1.4 |
| 2018 | 1,147 | 767 | 380 | 66.9% | −7.4 |
| 2019 | 1,030 | 633 | 397 | 61.5% | −5.4 |
| 2020 | 953 | 517 | 436 | 54.2% | −7.3 |
| 2021 | 592 | 277 | 315 | **46.8%** | −7.4 |

2021 is the first release year in which series outnumber films. Note 2021 is partial, ending 25 September.

## Q2 — Most common rating per type

| Type | Rating | Count |
|---|---|---|
| Movie | TV-MA | 2,062 |
| TV Show | TV-MA | 1,145 |

Overall: TV-MA 3,207, TV-14 2,160, TV-PG 863. 13 distinct ratings after folding `UR` into `NR`.

## Q3 — Titles released in 2020

953 total: 517 movies, 436 TV shows.

## Q4 — Top 5 producing countries

| Country | Titles |
|---|---|
| United States | 3,690 |
| India | 1,046 |
| United Kingdom | 806 |
| Canada | 445 |
| France | 393 |

122 distinct countries.

## Q5 — Longest movie

Black Mirror: Bandersnatch (2018), 312 minutes.

## Q6 — Added in the 5 years to the snapshot

8,422 titles added between 2016-09-25 and 2021-09-25.

## Q7 — Titles by Rajiv Chilaka

22 titles, 2009 to 2019, all films, predominantly the *Chhota Bheem* series. The highest count of any director in the catalogue.

## Q8 — TV shows with more than 5 seasons

99 shows. Longest: Grey's Anatomy (17 seasons), then NCIS and Supernatural (15 each).

## Q9 — Top 5 genres

| Genre | Titles | % of catalogue |
|---|---|---|
| International Movies | 2,752 | 31.2% |
| Dramas | 2,427 | 27.6% |
| Comedies | 1,674 | 19.0% |
| International TV Shows | 1,351 | 15.3% |
| Documentaries | 869 | 9.9% |

42 distinct genre tags. 6,787 titles carry more than one tag, so these are tag counts and must not be summed to a title total. Smallest tags: TV Shows (16), Classic & Cult TV (28).

## Q10 — India, top 5 release years by share

| Year | Titles | % of India total |
|---|---|---|
| 2017 | 111 | 10.61% |
| 2018 | 101 | 9.66% |
| 2019 | 93 | 8.89% |
| 2016 | 80 | 7.65% |
| 2020 | 77 | 7.36% |

Denominator is 1,046 India-tagged titles (normalised), not 972 (exact match).

## Q11 — Documentaries

869 titles carry the Documentaries tag, and all 869 are films. The series equivalent is a separate tag, Docuseries (395 titles).

## Q12 — Titles with no director

| Type | Count | Share of missing |
|---|---|---|
| TV Show | 2,446 | 92.9% |
| Movie | 188 | 7.1% |
| **Total** | **2,634** | 29.9% of catalogue |

## Q13 — Salman Khan, 10 years to snapshot

3 titles: Paharganj (2019), Prem Ratan Dhan Payo (2015), Mumbai Cha Raja (2012).

## Q14 — Top 10 actors in Indian-produced titles

| Actor | Titles |
|---|---|
| Anupam Kher | 40 |
| Shah Rukh Khan | 34 |
| Naseeruddin Shah | 31 |
| Akshay Kumar | 29 |
| Om Puri | 29 |
| Paresh Rawal | 28 |
| Amitabh Bachchan | 28 |
| Boman Irani | 27 |
| Kareena Kapoor | 25 |
| Ajay Devgn | 21 |

## Q15 — Keyword categorisation

| Method | Flagged |
|---|---|
| Naive `ILIKE '%kill%' OR '%violence%'` | 342 |
| Word-boundary regex | 217 |

125 of the 342 naive matches (37%) are false positives, such as "skill" and "killer whale".

## Q16 — Top 20 prolific directors

| # | Director | Titles | Dominant genre |
|---|---|---|---|
| 1 | Rajiv Chilaka | 22 | Children & Family Movies |
| 2 | Jan Suter | 21 | Stand-Up Comedy |
| 3 | Raúl Campos | 19 | Stand-Up Comedy |
| 4 | Marcus Raboy | 16 | Stand-Up Comedy |
| 5 | Suhas Kadav | 16 | Children & Family Movies |
| 6 | Jay Karas | 15 | Stand-Up Comedy |
| 7 | Cathy Garcia-Molina | 13 | International Movies |
| 8 | Jay Chapman | 12 | Stand-Up Comedy |
| 9 | Martin Scorsese | 12 | Dramas |
| 10 | Youssef Chahine | 12 | Dramas |
| 11 | Steven Spielberg | 11 | Children & Family Movies |
| 12 | Don Michael Paul | 10 | Action & Adventure |
| 13 | Anurag Kashyap | 9 | International Movies |
| 14 | David Dhawan | 9 | Comedies |
| 15 | Shannon Hartman | 9 | Stand-Up Comedy |
| 16 | Yılmaz Erdoğan | 9 | International Movies |
| 17 | Fernando Ayllón | 8 | Comedies |
| 18 | Hakan Algül | 8 | Comedies |
| 19 | Hanung Bramantyo | 8 | Dramas |
| 20 | Johnnie To | 8 | International Movies |

### Concentration of direction

| Titles directed | Directors |
|---|---|
| 1 | 3,971 |
| 2–4 | 903 |
| 5–9 | 107 |
| 10 or more | 12 |
| **Total distinct** | **4,993** |

## Q17 — Catalogue additions per year

| Year added | Titles | Movies | TV | Cumulative | YoY growth |
|---|---|---|---|---|---|
| 2015 | 82 | 56 | 26 | 138 | +241.7% |
| 2016 | 429 | 253 | 176 | 567 | +423.2% |
| 2017 | 1,188 | 839 | 349 | 1,755 | +176.9% |
| 2018 | 1,649 | 1,237 | 412 | 3,404 | +38.8% |
| 2019 | **2,016** | 1,424 | 592 | 5,420 | +22.3% |
| 2020 | 1,879 | 1,284 | 595 | 7,299 | −6.8% |
| 2021 | 1,498 | 993 | 505 | 8,797 | −20.3% |

Additions peak in 2019. 2021 is partial.

## Q18 — Acquisition lag (years between release and addition)

| Type | Titles | Mean lag | Median lag | Within 1 year |
|---|---|---|---|---|
| Movie | 6,131 | 5.73 | 2 | 49.6% |
| TV Show | 2,666 | 2.30 | 0 | 67.4% |

Counts here total 8,797, not 8,807, because 10 titles have no `date_added`.

---

## Relational results (normalised schema)

### Table sizes

| Table | Rows |
|---|---|
| `dim_title` | 8,807 |
| `dim_person` | 40,948 |
| `dim_country` | 122 |
| `dim_genre` | 42 |
| `bridge_title_cast` | 64,124 |
| `bridge_title_genre` | 19,323 |
| `bridge_title_country` | 10,012 |
| `bridge_title_director` | 6,977 |

Bridge tables exceed `dim_title` because one title contributes one row per value. After any bridge join, counts must use `COUNT(DISTINCT show_id)`.

### J3 — Format partitioning of the genre taxonomy

All 42 genre tags are either 100% film or 100% series. Tag pairs: Dramas / TV Dramas, Comedies / TV Comedies, Documentaries / Docuseries, Action & Adventure / TV Action & Adventure, Horror Movies / TV Horror, Sci-Fi & Fantasy / TV Sci-Fi & Fantasy, Thrillers / TV Thrillers, International Movies / International TV Shows.

### J6 — India versus United States genre mix

| Genre | India | United States |
|---|---|---|
| International Movies | 864 | 166 |
| Dramas | 662 | 835 |
| Comedies | 323 | 680 |
| Independent Movies | 167 | 390 |
| Action & Adventure | 137 | 404 |
| Documentaries | 27 | 512 |
| Children & Family Movies | 26 | 390 |

### J7 — People who both directed and acted

484 people appear in both roles. Yılmaz Erdoğan is the most balanced (9 directed, 8 acted).

### J8 — Top co-production pairs

| Countries | Co-productions |
|---|---|
| United Kingdom & United States | 279 |
| Canada & United States | 217 |
| France & United States | 125 |
| Germany & United States | 88 |
| France & United Kingdom | 67 |

### J9 — Genre share shift, pre-2018 versus 2018–2021

| Genre | Pre-2018 share | Modern share | Direction |
|---|---|---|---|
| International TV Shows | 5.34% | 9.25% | gaining |
| TV Dramas | 2.78% | 5.55% | gaining |
| Crime TV Shows | 1.48% | 3.74% | gaining |
| Docuseries | 1.40% | 2.93% | gaining |
| Dramas | 14.26% | 10.23% | losing |
| Comedies | 10.15% | 6.63% | losing |
| International Movies | 15.66% | 12.29% | losing |

Every gaining tag is a series tag. This is the genre-level mechanism behind the 60/40 shift.

### J10 — Average film runtime by genre (100+ titles)

| Genre | Films | Avg minutes |
|---|---|---|
| Classic Movies | 116 | 118.6 |
| Action & Adventure | 859 | 113.5 |
| Dramas | 2,427 | 113.1 |
| Documentaries | 869 | 81.6 |
| Children & Family Movies | 641 | 79.9 |
| Stand-Up Comedy | 343 | 67.3 |

### J11 — Country leaderboard

| Country | Titles | Movie % | Mean lag (yrs) |
|---|---|---|---|
| United States | 3,690 | 74.6% | 5.69 |
| India | 1,046 | 92.0% | 6.69 |
| United Kingdom | 806 | 66.3% | 4.94 |
| Japan | 318 | 37.4% | 5.00 |
| South Korea | 231 | 26.4% | 1.77 |
| Spain | 232 | 73.7% | 1.72 |

India is almost entirely film. Japan and South Korea are series-led. Spain and South Korea have the shortest acquisition lag, consistent with recent originals commissioning.

### J12 — Internal contradiction

209 titles are tagged International Movies but have no country recorded, so the genre tag and the country field are populated independently and neither can repair the other.

---

## Validation

`06_validation.sql` runs 22 assertions across four layers: raw load integrity, cleaning correctness, ETL completeness, and headline findings. On a clean rebuild, 22 of 22 report PASS.
