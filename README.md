# General moderation decision analysis

This repo contains checked in data and analysis for understanding General's moderation decisions.

As a registry maintainer, I want to help make good decisions in line with the past.

## Analyses

So far I have focused on 3-letter package names. You can see my analysis in [./three-letter-names](./three-letter-names/README.md).

## Scripts

### `fetch-prs.jl`

Fetches manually-merged "new package" PRs from JuliaRegistries/General with full metadata and comments.

**Prerequisites:** Julia 1.12, GitHub CLI (`gh`) authenticated

**Usage:** `./fetch-prs.jl` (resume anytime - progress auto-saved)

**Output:** `data/A/Abc-pr123.json` (organized by first letter)

### `extract-precedents.jl`

Hybrid extraction tool combining code-based patterns (free) with LLM analysis (cheap) to understand moderation decisions.

#### What it extracts

**Code-based (free):**
- AutoMerge guideline violations (name length, format, version, compat, etc.)
- Library wrapper detection
- Related PR references
- Slack channel mentions

**LLM-based (using `llm` CLI):**
- Comment stance classification (pro/anti/neutral/unrelated merge)
- Influence ratings (1-5 scale) for each comment
- Explicit justification categories (wrapper, acronym, precedent, etc.)

#### Usage

```bash
# Single file
./extract-precedents.jl data/A/ABC-pr12345.json

# Batch process entire directory (resumable - skips existing analysis)
./extract-precedents.jl data/
```

**Default model:** `gemini/gemini-2.0-flash` (cheap: ~$0.10 per 1M input tokens)

#### Output

Creates analysis files in `analysis/` mirroring the `data/` structure:
- `data/A/ABC-pr12345.json` → `analysis/A/ABC-pr12345-analysis.json`

Each analysis includes violations, wrapper info, justifications, comment classifications with influence scores, decision metadata, and token usage estimates.
