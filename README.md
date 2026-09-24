# Peek — Product Analyst Data Challenge

[![CI](https://github.com/abrahamperz/peek-data-challenge/actions/workflows/ci.yml/badge.svg)](https://github.com/abrahamperz/peek-data-challenge/actions/workflows/ci.yml)

Analysis of the public **[`bigquery-public-data.thelook_ecommerce`](https://console.cloud.google.com/marketplace/product/bigquery-public-data/thelook-ecommerce)** dataset (a synthetic
ecommerce business), covering monthly financials, customer retention, and a
free-shipping scenario.

- **Author:** Abraham Perez Martinez
- **Dataset window:** 2019-02 → 2026-08 (91 complete months)
- **Snapshot:** 2026-09-24

> **Note on the data.** `thelook_ecommerce` is a *synthetic* dataset that Google regenerates over
> time. Comparing 2026-09-23 with 2026-09-24 we saw the historical months shift (rows added, the
> earliest month rolled forward, and orders seeded a few days past "today"). We didn't measure the
> exact cadence — the point is the data is not static — so the figures below are a **frozen snapshot
> taken 2026-09-24** (cached in [`data/*.csv`](data/)). A fresh run on another day will likely return
> slightly different numbers; the *story* is stable.

## Key findings

thelook is a **high-acquisition, low-retention** business. The top line looks great, but almost
all of the growth is new customers, not repeat behavior.

| Metric | Value |
|---|---|
| All-time completed revenue | **~$2.5M** |
| Latest full month (2026-08) | **$132.9k** revenue · **1,535** orders |
| Average gross margin | **~52%** |
| 90-day churn rate | **avg ~96%** (recently ~94%) |
| Month-1 cohort retention | **~3%** |
| Returning-customer revenue share | **~9% avg → ~16% recently** (peaks near 20%, up from near zero) |

**Bottom line:** growth is real and durable, but the business acquires customers far faster than
it retains them. The biggest lever is not more acquisition — it's closing the month-0 → month-1
retention cliff.

---

## Deliverables & links

| Deliverable | Where |
|---|---|
| **Part 1 — SQL** (Tasks A–D + cohort stretch) | [`sql/part1_queries.sql`](sql/part1_queries.sql) |
| **Part 2 — Notebook** (analysis + 5 figures) | [`analysis/peek_analysis.ipynb`](analysis/peek_analysis.ipynb) |
| **Part 2 — Cached query outputs** | [`data/*.csv`](data/) — so the notebook reproduces without BigQuery |
| **Part 2 — Slides** (interactive HTML deck) | [`deck/index.html`](deck/index.html) — self-contained; open in any browser · [PDF export](deck/peek_deck.pdf) |
| **Part 3 — How I used AI** (written response) | [Jump to Part 3 ↓](#part-3--how-i-used-ai) — in this README |
| **CI** — 3 checks on every push | [`.github/workflows/ci.yml`](.github/workflows/ci.yml)<br>• **lint** (clean-code) — SQLFluff enforces readable, consistent SQL: uppercase keywords, explicit aliasing, column order, line length<br>• **format** — fails unless every file is already canonically formatted (`sqlfluff format`), so SQL arrives clean<br>• **typecheck** — BigQuery *dry run* validates every table/column/type against the live schema; catches a hallucinated column or wrong type, bills 0 bytes |

---

## Clean code — SQL style & linting

Every query is checked in CI against the rules pinned in [`.sqlfluff`](.sqlfluff). **Lint** reports
style issues; **format** rewrites the file to satisfy them (the format job fails the build unless the
SQL is already canonically formatted). Anything not listed here runs on SQLFluff's defaults.

**General config**

| Rule | Value | What it does |
|---|---|---|
| `dialect` | `bigquery` | Parses BigQuery Standard SQL syntax. |
| `templater` | `raw` | Treats SQL as plain text (no Jinja/dbt templating). |
| `max_line_length` | `120` | No line exceeds 120 characters — readability. |
| `indent_unit` / `tab_space_size` | spaces, `2` | Indents with 2 spaces (no tabs). |

**Style rules**

| Rule | Policy | Example |
|---|---|---|
| `capitalisation.keywords` | `UPPER` | `SELECT`, `FROM`, `WHERE` |
| `capitalisation.functions` | `UPPER` | `SUM()`, `DATE_TRUNC()` |
| `capitalisation.literals` | `UPPER` | `NULL`, `TRUE`, `FALSE` |
| `capitalisation.identifiers` | `lower` | `order_revenue`, `params` |
| `aliasing.table` | `explicit` | `order_items AS oi` (not `order_items oi`) |
| `aliasing.column` | `explicit` | `SUM(sale_price) AS revenue` |

The idea: **language keywords in UPPERCASE, your own names in lowercase**, so syntax reads as
distinct from schema; explicit `AS` aliases avoid the hard-to-read `table alias` juxtaposition.
(A third CI job, the BigQuery **dry-run typecheck**, validates every table/column/type against the
live schema — that one enforces correctness, not style.)

---

## Repository structure

```
.
├── sql/
│   ├── part1_queries.sql        # Part 1 — all SQL (Tasks A–D + cohort stretch), each standalone
│   ├── run_queries.sh           # Regenerates data/*.csv from the SQL (uses YOUR project id)
│   └── dryrun.sh                # BigQuery dry-run typecheck (used by CI; bills 0 bytes)
├── data/                        # Part 2 inputs — cached query outputs, so it reproduces without BigQuery
│   ├── taskA_monthly_financials.csv
│   ├── taskB_new_vs_returning.csv
│   ├── taskC_churn_90d.csv
│   ├── taskC_cohort_retention.csv
│   ├── taskD1_monthly_trend.csv
│   ├── taskD2_prepost_valueband.csv
│   ├── taskD3_traffic_source.csv
│   └── peek_data.xlsx           # All task outputs in one workbook (one sheet per task)
├── analysis/
│   ├── peek_analysis.ipynb      # Part 2 — notebook: 5 visuals + recommendations
│   └── charts/*.png             # Rendered figures (5)
├── deck/
│   ├── index.html               # Part 2 — interactive slide deck (self-contained; open in any browser)
│   └── peek_deck.pdf            # Same deck exported to PDF (8 slides, one per page)
├── .github/workflows/
│   └── ci.yml                   # CI — lint · format · BigQuery dry-run typecheck (on every push)
├── .sqlfluff                    # SQLFluff config (BigQuery dialect; lint + format rules)
├── .env.example                 # Copy to .env, set GOOGLE_CLOUD_PROJECT (not a secret)
└── README.md                    # This file (assumptions, definitions, how-to-run, Part 3)
```

> **No credentials or private data are committed.** The challenge PDF and any credential files are
> git-ignored. Everything here runs against a public BigQuery dataset and is fully reproducible.

---

## How to run

### Part 1 — SQL (BigQuery)

Any GCP project with BigQuery access works, including a free **Sandbox** project (no billing needed).

```bash
# Example with the bq CLI — run any single task block from the file
bq query --use_legacy_sql=false --project_id=YOUR_PROJECT < <(sed -n '37,75p' sql/part1_queries.sql)
```

Or paste a task block into the BigQuery console. **Each task is a self-contained query** with its own
`params` CTE at the top — change the dates there to re-scope; nothing is hard-coded.

### Regenerate the CSVs from the SQL (optional — closes the loop)

The `data/*.csv` files are a cached snapshot so Part 2 runs offline. To regenerate them from scratch
against BigQuery, using **your own** project:

```bash
cp .env.example .env                          # then edit .env: GOOGLE_CLOUD_PROJECT=your-gcp-project-id
gcloud auth application-default login         # one-time auth (credentials live only on your machine)
bash sql/run_queries.sh                       # runs all 7 queries → data/*.csv
```

The project id only says which project **runs/bills** the query — it's not a credential and isn't
baked into the SQL, so you supply your own. The queries read only the public dataset, so a free
Sandbox project works. (thelook is synthetic and keeps generating rows toward "today," so a fresh
run may return a few more recent months than the committed snapshot.)

### Part 2 — Notebook (Python)

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install pandas matplotlib jupyter nbformat
jupyter notebook analysis/peek_analysis.ipynb   # or: jupyter nbconvert --to notebook --execute --inplace analysis/peek_analysis.ipynb
```

The notebook reads only the CSVs in `data/`, so it reproduces every figure **without touching
BigQuery**.

---

## Definitions & assumptions

These follow the challenge brief and are applied consistently across every query.

| Term | Definition |
|---|---|
| **Completed sale** | `order_items.status = 'Complete' AND returned_at IS NULL`. Cancelled/returned/processing items are excluded from revenue and order counts. |
| **Revenue** | `SUM(order_items.sale_price)` over completed items. |
| **Order** | `COUNT(DISTINCT order_id)` among completed line items. **Units** = count of completed line items. |
| **AOV** | Revenue ÷ completed orders. |
| **COGS / Gross profit** | COGS = `SUM(inventory_items.cost)` joined via `inventory_item_id`. Gross profit = Revenue − COGS; gross margin = gross profit ÷ revenue. |
| **Activation (first purchase)** | A user's **first completed order**. Used for new-vs-returning and cohort assignment. |
| **New customer (in month M)** | A customer whose first completed order falls in month M. |
| **Returning customer (in month M)** | A customer active in M whose first completed order was **before** M. |
| **Active customer (in month M)** | A customer with ≥1 completed order in M. |
| **90-day churn (for month M)** | Of customers active in M, the share with **no** completed order in the following 90 days. Only computed for months whose full 90-day forward window is observed (last ~3 months are dropped). |
| **Cohort retention** | Rows = first-purchase month; `month_offset` = months since first purchase (0 = acquisition month, always 100%); value = share of the cohort with a completed order that month. |
| **Value band (Task D)** | Order-level: `gte_100` (order value ≥ $100) vs `lt_100` (< $100). |

### Date-window choices (and why)

- **Start = 2019-01-01** — a fixed lower bound at/just before the earliest order month (currently 2019-02). Anchoring here keeps the window stable even as the synthetic dataset's earliest month drifts forward over time.
- **End = `DATE_TRUNC(CURRENT_DATE(), MONTH)` (exclusive)** — the **current partial month is
  excluded** so MoM growth and trend lines aren't distorted by an incomplete month. (thelook is
  synthetic and generates rows up to ~today.)
- **Churn/cohort maturity** — churn is only reported for months with a fully-observed 90-day forward
  window; cohort offsets are shown where the follow-up month has elapsed. This avoids reporting
  artificially "low" churn or retention for months that simply haven't had time to play out.

### On the 90-day churn definition (limitations & how I'd refine it)

This churn metric is deliberately simple, and it has real limitations:

- **It's calendar-anchored, not activity-anchored.** The 90-day window starts at *month-end*, so a
  customer who buys on the 1st effectively gets ~120 days of runway while one who buys on the 30th gets
  ~90. A cleaner definition anchors the window to each customer's **own last order date**.
- **It's a single hard cutoff, so "churn" is binary and non-sticky.** A customer with a long-but-real
  cadence (e.g., a seasonal buyer every ~100 days) is labeled churned even though they aren't gone, and
  a "churned" customer can silently reappear the next month.
- **Order-only signal.** The dataset has no logins, sessions, or email engagement, so "no completed
  order in 90 days" can't distinguish *dormant-but-alive* from *truly gone*.

**How I'd refine it in a real product setting:** anchor the window to each customer's last purchase,
choose the horizon from the actual **inter-purchase-time distribution** (e.g., the 75th/90th percentile
of the gap between orders) instead of a flat 90 days, and move from a hard cutoff to a **survival /
time-to-next-purchase model** — blending behavioral signals (visits, cart adds, app opens, email
opens) so churn reflects true disengagement rather than a single missed order.

---

## Part 1 — SQL (`sql/part1_queries.sql`)

| Task | What it produces |
|---|---|
| **A — Monthly financials** | month, revenue, orders, units, AOV, MoM revenue growth (window `LAG`). |
| **B — New vs Returning** | active / new / returning customers, revenue split, and % of revenue from returning customers, by month. |
| **C — 90-day churn** | active customers, churned-in-90d, churn rate, for fully-observed months only. |
| **C (stretch) — Cohort retention** | long-format cohort × offset retention table. |
| **D1 — Profitability trend** | monthly revenue, orders, AOV, gross profit, gross margin. |
| **D2 — Free-shipping scenario** | difference-in-differences frame: value band (≥$100 vs <$100) × pre/post period. |
| **D3 — Segment view** | pre/post AOV & revenue by `traffic_source`. |

Every query is parameterized and standalone. Result sets are cached in `data/` as CSVs.

---

## Part 2 — Analysis & visualization (`analysis/peek_analysis.ipynb`)

Five figures, each built to a single-axis, colorblind-safe standard (no dual-axis charts; the
categorical palette passes CVD-separation checks):

1. **New vs Returning revenue mix** — absolute stacked revenue + the returning-revenue share line.
   Acquisition carries the top line; returning share has climbed from ~0 to ~16% (peaking near 20%).
2. **Revenue & orders MoM** — three stacked panels (revenue, orders, MoM growth). Durable growth;
   MoM swings compress as the base matures.
3. **90-day churn vs revenue** — churn stays extreme (~96% avg) even as revenue scales ~30×.
4. **Free-shipping impact (scenario)** — AOV pre/post frame + ≥$100 (treatment) vs <$100 (control)
   difference-in-differences bars. *This policy is not in the data — it's an analysis scaffold; see
   the scenario note below.*
5. **Cohort retention heatmap** (stretch) — the pale grid past month 1 is the visual signature of
   the retention problem.

### On the free-shipping scenario (honesty note)

thelook has **no shipping-fee field and no free-shipping policy** in the data. Task D therefore builds
the **analysis frame** you'd use to measure such a policy — a difference-in-differences design where
orders ≥$100 are the "treatment" group and <$100 the "control," compared pre/post a launch date —
rather than inventing an effect. In the synthetic data the bars are flat by construction. To actually
measure impact we'd need: an order-level `shipping_fee`, the policy launch date, and ideally a holdout
group so the pre/post read is causal rather than directional.

---

## Recommendations

1. **Attack retention, not just the funnel.** With ~96% 90-day churn and ~3% month-1 retention, a few
   points of retention compound faster than equivalent spend on acquisition. Stand up a lifecycle
   program — post-purchase onboarding, a day-30/60 win-back — explicitly targeting the month-0 →
   month-1 cliff, and track repeat-rate at 30/60/90 days as the north-star.
2. **Grow the returning-revenue share deliberately.** It has drifted up to ~16% (peaking near 20%) on its own; make it a
   goal. Test loyalty / replenishment nudges on first-time buyers in the highest-margin categories,
   and measure incremental repeat purchases, not just redemption.
3. **Instrument before launching pricing/shipping policies.** Add order-level `shipping_fee` and promo
   flags, define the launch date, and reserve a holdout. That turns a "free shipping over $100" launch
   from a directional guess into a measurable difference-in-differences experiment.

---

## Part 3 — How I used AI

I used **Claude (Claude Code)** as an analysis pair-programmer across all three parts. The workflow:

- **Setup & exploration.** Claude helped me stand up a free BigQuery Sandbox project from scratch, then
  profiled the dataset (date range, `status` distribution, the `inventory_items` join path for COGS,
  available event/traffic fields) so the query definitions matched the actual schema rather than
  assumptions.
- **SQL authoring & validation.** I had Claude draft each task, then I **ran every query live against
  BigQuery** and checked the outputs before finalizing. Bugs it caught this way included a reserved-word
  alias collision (`rows`) and the need to drop not-yet-observed months from the churn calculation.
- **Visualization.** Claude generated the notebook and figures, applying a strict chart standard
  (single-axis only, colorblind-validated palette). I reviewed each rendered chart and had it correct
  claims that didn't match the plot — e.g. an early "churn is flat ~93%" title was revised to the
  accurate "avg ~96%, recently ~93%" once the average line was actually computed.

**Example prompt I used:**

> "Write a BigQuery Standard SQL query for 90-day churn by month: of customers with a completed order in
> month M, what share have no completed order in the next 90 days? Parameterize the date window with a
> `params` CTE (no hard-coded dates), and only output months whose full 90-day window has elapsed."

**How I validated AI output.** I treated every AI result as a draft to verify, not a final answer:
(1) ran all SQL against live BigQuery and sanity-checked magnitudes and row counts; (2) cross-checked
that definitions (completed sale, activation, churn window) were applied identically across tasks;
(3) visually inspected each chart and reconciled every headline number against the underlying CSV
before it went in this README; (4) wired up **continuous integration**
([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) so every push automatically re-checks the SQL —
**lint** and **format** (SQLFluff, BigQuery dialect) for consistency, plus a **BigQuery dry-run
typecheck** that validates every table, column, and type reference against the live schema without
billing any bytes. That last check mechanically catches the failure mode AI is most prone to — a
hallucinated column or a mismatched type — on every commit, not just once by eye. (CI checks structure
and references; it does not replace the human sanity-checks on magnitudes and business logic above.)
Where the data couldn't support a claim (the free-shipping policy), I kept the analysis honest by
labeling it a scenario scaffold rather than reporting a fabricated effect.
