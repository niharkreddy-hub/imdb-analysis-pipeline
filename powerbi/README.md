# Power BI report build guide

**Status: SQL sources and measure definitions prepared. A Power BI report, screenshots and working report link are still pending.** Synthetic test values must not be presented as IMDb findings.

## Data connection and model

Finish the full-data workflow in the root README and review `etl.rejects` first. In Power BI Desktop, connect to the project's PostgreSQL database using the PostgreSQL connector. Import the views below and rename the Power BI tables exactly as shown. Keep credentials in connection settings, outside the repository.

| PostgreSQL view | Power BI name | Grain |
|---|---|---|
| `reporting.titles` | `Titles` | One row per title, including unrated titles |
| `reporting.title_genres` | `TitleGenres` | One row per title–genre assignment |
| `reporting.episodes` | `Episodes` | One row per episode with its series identity |

Create a **one-to-many, single-direction** relationship from `Titles[tconst]` to `TitleGenres[tconst]`. Leave `Episodes` separate: its page uses episode-specific slicers, so a title-type filter cannot accidentally remove its parent series. Do not flatten `TitleGenres` into `Titles`; that would duplicate ratings and votes for multi-genre titles.

Use text for IDs, whole numbers for year/runtime/votes/season/episode, decimal numbers for ratings, and Boolean for `is_adult`. Set numeric identifiers and years to **Don't summarize**. Use the separate definitions in [measures.dax](measures.dax); format coverage as percentages and rating measures to two decimal places.

## Pages and interactions

| Page | Question | Visuals | Filters and definitions |
|---|---|---|---|
| 1. Content & coverage | What does this snapshot contain, and how much is rated? | Title count, rated titles and coverage cards; title-type bar; movie titles by start year; genre counts; runtime distribution | Type, start-year range and adult flag from `Titles`. State defaults visibly. Movie runtime chart excludes missing/zero and >300 minutes; disclose exclusions. |
| 2. Ratings & votes | How do ratings vary with voting activity? | Mean title rating and vote-total cards; highest/lowest movie tables; rating-vote scatter | Movie type; a visible numeric `num_votes` filter, default >=50,000. Use `title_label` to identify each scatter point and logarithmic vote axis. Rank with explicit tie-breaks: rating, votes, ID. |
| 3. Series & seasons | How do episode ratings vary across observed seasons? | Episode coverage cards; season mean line; episode details | Single-select `Episodes[series_label]`; regular seasons >0. X=season number, Y=`Mean Episode Rating` from episode rows. Include rated/observed episode counts in tooltips. |

Use `Genre Title Count` on the genre bar. Genres overlap: their counts can sum above the number of titles. With the single-direction relationship, clicking a genre does not filter title cards. Disable that chart's interactions with title-level visuals, and label it as a breakdown within the other page filters. Do not add a genre slicer without implementing and testing the required bridge-filter logic.

On the series page, `series_label` contains the unique ID to distinguish identical series names. Season 0 represents specials and is excluded from the regular-season trend. Unrated episodes contribute to observed counts, but not the rating mean. The last observed rated season is not necessarily a show's final season.

The scatter must have one point per title. Check Power BI's displayed point/data-reduction limit on the actual report; apply a visible cohort filter if needed. Do not describe a reduced visual as the full dataset. Use Ratings Q8 for the calculated correlation, stratified by title type; association is not causation.

## Evidence required before portfolio publication

1. Record source download date, file hashes, import counts, rejected row/token counts, PostgreSQL version and report refresh time. Do not infer the source date from a screenshot.
2. Reconcile a title count, a vote total, a filtered rating mean and one series-season mean against SQL with identical filters. Check the same-named-series case.
3. Test slicers, cross-filtering, nulls and empty selections. Check titles, units, tooltips, contrast and clipped labels.
4. Save the PBIX locally. It is ignored by this repository; add it only deliberately after reviewing size and embedded data. A link and screenshots can document the report without committing the model.
5. Add genuine page screenshots under `docs/screenshots/` and embed them in the root README. Use meaningful filenames such as `content-overview.png`; no placeholder images.
6. Add the actual report URL with an access note. Verify access from a separate viewer context. Ordinary Power BI sharing may require sign-in and permissions. Public publishing is a separate decision; do not use it merely to create a portfolio URL.
7. Write three observations from the verified snapshot, each with its filters, counts and limitations. Do not invent findings, impact or recommendations before the run.

Useful sources: [PostgreSQL connector](https://learn.microsoft.com/en-us/power-query/connectors/postgresql), [report sharing](https://learn.microsoft.com/en-us/power-bi/collaborate-share/service-share-dashboards), [public publishing](https://learn.microsoft.com/en-us/power-bi/collaborate-share/service-publish-to-web).
