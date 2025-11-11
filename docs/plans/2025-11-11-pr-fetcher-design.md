# PR Fetcher Design

**Date:** 2025-11-11
**Purpose:** Fetch PR body text, comments, and metadata from JuliaRegistries/General for manually-merged new package registrations

## Overview

This tool extracts historical moderation decisions from the General registry by fetching PRs that were manually reviewed (not auto-merged by bots). The data will be used to analyze past maintainer decisions, precedents, and reasoning.

## Requirements

### Filters
- **Repository:** JuliaRegistries/General
- **Label:** "new package"
- **State:** merged or closed
- **Exclude merged by:** "JuliaTagBot" and "jlbuild" (automated merges)

### Data to Extract
- PR metadata: number, title, author, state, created date, merged date, merged by user
- PR body text
- All comments (general and review comments)

### Constraints
- Use `gh` CLI for all API interactions (pre-configured auth)
- Respect GitHub rate limits (5000 requests/hour)
- Fully resumable (script can be stopped and restarted)
- Long-running job (overnight execution expected for complete historical fetch)

## Architecture

**Three-stage pipeline with automatic resumability:**

1. **Stage 1: Fetch PR List** - Get complete list of PRs matching filters via GraphQL
2. **Stage 2: Filter and Prepare** - Exclude bots and already-downloaded PRs
3. **Stage 3: Fetch Details** - Download full PR data and write JSON files

Each stage checks for existing output files and skips if already completed. No manual stage selection needed.

## Data Structures

### Cache Directory Structure
```
cache/
  pr-list.json          # Raw list from GraphQL (Stage 1 output)
  to-fetch.json         # Filtered list (Stage 2 output)
  stage3-progress.json  # Last completed PR number for Stage 3
  failed.json           # Failed PRs with error details
```

### Output Directory Structure
```
data/
  A/
    Abc-pr123.json
    Animal-pr1245.json
  B/
    Builds-pr3242.json
    Blarg-pr2342.json
  ...
```

Organization: `data/{FIRST_LETTER}/{PackageName}-pr{NUMBER}.json`

### JSON Output Format
```json
{
  "pr_number": 123,
  "title": "New package: PackageName v0.1.0",
  "package_name": "PackageName",
  "author": "username",
  "state": "MERGED",
  "created_at": "2023-01-15T10:30:00Z",
  "merged_at": "2023-01-16T14:20:00Z",
  "merged_by": "maintainer-username",
  "body": "Full PR body text...",
  "comments": [
    {
      "author": "reviewer1",
      "created_at": "2023-01-15T11:00:00Z",
      "body": "Comment text..."
    }
  ],
  "review_comments": [
    {
      "author": "reviewer2",
      "created_at": "2023-01-15T12:00:00Z",
      "body": "Review comment text..."
    }
  ]
}
```

## Stage Details

### Stage 1: Fetch PR List

**Purpose:** Get complete list of PRs with "new package" label using GraphQL

**Implementation:**
- GraphQL search via `gh api graphql`
- Query: `repo:JuliaRegistries/General label:"new package" is:merged is:closed`
- Fields: number, title, author{login}, state, mergedBy{login}, createdAt, mergedAt
- Handle pagination with `pageInfo { endCursor hasNextPage }`
- Write to `cache/pr-list.json`

**Output:** Complete list of all "new package" PRs (thousands)

**Skip condition:** If `cache/pr-list.json` exists

### Stage 2: Filter and Prepare

**Purpose:** Exclude automated merges and already-downloaded PRs

**Implementation:**
- Load `cache/pr-list.json`
- Filter out: `mergedBy.login == "JuliaTagBot"` or `mergedBy.login == "jlbuild"`
- Parse package name from title using regex: `r"New package:\s+(\w+)(?:\.jl)?"`
- Check if output file exists: `data/{FIRST_LETTER}/{PackageName}-pr{NUMBER}.json`
- Skip if file already exists (already downloaded)
- Handle parse failures gracefully (log to failed.json)
- Write filtered list to `cache/to-fetch.json`

**Output:**
- `cache/to-fetch.json` with PRs to download (expected: hundreds after filtering)
- Summary: "Filtered: X total → Y manual merges → Z to fetch (A already downloaded)"

**Skip condition:** If `cache/to-fetch.json` exists

### Stage 3: Fetch Details

**Purpose:** Download full PR data and write JSON files

**Implementation:**
- Load `cache/to-fetch.json` and `cache/stage3-progress.json` (if exists)
- Skip PRs <= last completed PR number from progress file
- For each PR:
  - Fetch details: `gh pr view {NUMBER} --repo JuliaRegistries/General --json body,comments`
  - Fetch reviews: `gh api repos/JuliaRegistries/General/pulls/{NUMBER}/reviews`
  - Parse package name from title
  - Create directory: `data/{FIRST_LETTER}/` (if needed)
  - Write JSON: `data/{FIRST_LETTER}/{PackageName}-pr{NUMBER}.json`
  - Update `cache/stage3-progress.json` with current PR number
  - Delay 0.5 seconds between requests

**Progress tracking:** Write PR number to `cache/stage3-progress.json` after each successful file write

**Resume logic:** On restart, read progress file and skip all PRs <= last completed number

**Skip condition:** Always runs (checks progress file internally for resume point)

## Rate Limiting Strategy

**Baseline politeness:** 0.5 second delay between all requests

**Rate limit handling:**
- Let `gh` handle rate limiting initially
- If `gh` returns rate limit error:
  - Check `gh api rate_limit` for reset time
  - Sleep until reset time
  - Retry request (doesn't count against retry limit)

**Why this approach:** More efficient than checking rate limit before every request; `gh` provides good error messages when limits are hit

## Error Handling

### Retry Logic

**Network/API errors:**
- Exponential backoff: 1s, 2s, 4s, 8s, 16s
- Up to 5 retries
- After 5 failures: log to `cache/failed.json` and continue

**Rate limit errors:**
- Wait until reset time (as indicated by `gh api rate_limit`)
- Retry (doesn't count against 5-retry limit)

**Parse errors (malformed title):**
- Log to `cache/failed.json`
- Continue to next PR

**Missing data (null body/comments):**
- Log warning
- Write JSON with available data

### Failed PR Tracking

File: `cache/failed.json`

Format:
```json
[
  {
    "pr_number": 123,
    "stage": "fetch_details",
    "error_type": "network_timeout",
    "error_message": "Connection timed out after 5 retries",
    "timestamp": "2025-11-11T10:30:00Z"
  }
]
```

Error types: `network_timeout`, `api_error`, `parse_error`, `missing_data`

## Script Invocation

**Command:** `julia fetch-prs.jl`

**Behavior:** Automatically detects completed stages and resumes from where it left off

**Optional flags:**
- `--refetch-list`: Delete `cache/pr-list.json` and re-run Stage 1
- `--refilter`: Delete `cache/to-fetch.json` and re-run Stage 2

## Progress Logging

**Stage 1:** "Fetched page 5/? (500 PRs so far)..."

**Stage 2:** "Filtered: 5000 total → 150 manual merges → 120 to fetch (30 already downloaded)"

**Stage 3:** "Progress: 45/120 fetched... (rate limit wait at 10:30 AM, resuming at 11:00 AM)"

**Completion:** "Done! 115 successful, 5 failed (see cache/failed.json)"

## Implementation Language

**Julia** as scripting language (per user preference)

Reference: https://github.com/ninjaaron/administrative-scripting-with-julia for Julia scripting patterns

## Package Name Parsing

Extract from PR title using regex: `r"New package:\s+(\w+)(?:\.jl)?"`

Handles both formats:
- "New package: PackageName v0.1.0"
- "New package: PackageName.jl v0.1.0"

Graceful failure: If parse fails, log to failed.json and skip PR
