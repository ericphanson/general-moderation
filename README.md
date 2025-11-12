# General moderation decision analysis

This repo contains checked in data and analysis for understanding General's moderation decisions.

As a registry maintainer, I want to help make good decisions in line with the past.

## Analyses

So far I have focused on 3-letter package names. You can see my analysis in [./three-letter-names](./three-letter-names/README.md).

## Scripts

### `fetch-prs.jl`

Fetches manually-merged "new package" PRs from JuliaRegistries/General with full metadata and comments.

### Prerequisites

- Julia 1.12
- GitHub CLI (`gh`) authenticated

### Usage

```bash
./fetch-prs.jl
```

The script runs three stages automatically:
1. Fetches all PRs with "new package" label
2. Filters out bot merges (JuliaTagBot, jlbuild)
3. Downloads full PR details (body, comments, reviews)

Resume any time by running again - progress is saved after each page/PR.

#### Options

```bash
./fetch-prs.jl --refetch-list  # Re-fetch PR list from scratch
./fetch-prs.jl --refilter      # Re-run filtering stage
```

### Output

```
data/
  A/Abc-pr123.json
  B/Builds-pr3242.json
  ...
```

Each file contains PR metadata, package name, body, comments, and review comments.

### `extract-precedents.jl`

Runs cheap LLMs to do some basic analysis on the comments and justifications, as well as non-ML text extraction.

Populates `analysis/`.
