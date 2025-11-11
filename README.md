# General Registry PR Fetcher

Fetches manually-merged "new package" PRs from JuliaRegistries/General with full metadata and comments.

## Prerequisites

- Julia
- GitHub CLI (`gh`) authenticated

## Usage

```bash
./fetch-prs.jl
```

The script runs three stages automatically:
1. Fetches all PRs with "new package" label
2. Filters out bot merges (JuliaTagBot, jlbuild)
3. Downloads full PR details (body, comments, reviews)

Resume any time by running again - progress is saved after each page/PR.

### Options

```bash
./fetch-prs.jl --refetch-list  # Re-fetch PR list from scratch
./fetch-prs.jl --refilter      # Re-run filtering stage
```

## Output

```
data/
  A/Abc-pr123.json
  B/Builds-pr3242.json
  ...
```

Each file contains PR metadata, package name, body, comments, and review comments.

## Cache

```
cache/
  pr-list.json          # All PRs (JSONLines format)
  to-fetch.json         # Filtered PRs to download
  stage3-progress.json  # Last completed PR
  failed.json           # Failed PRs with errors
```
