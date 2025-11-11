# PR Fetcher Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a resumable Julia script to fetch manually-merged "new package" PRs from JuliaRegistries/General with full metadata and comments.

**Architecture:** Three-stage pipeline with automatic resumability. Stage 1 fetches PR list via GraphQL, Stage 2 filters bots and existing files, Stage 3 downloads full details. Each stage checks for existing output and skips if complete.

**Tech Stack:** Julia scripting, `gh` CLI for GitHub API, JSON for data storage

---

## Task 1: Project Structure and Dependencies

**Files:**
- Create: `fetch-prs.jl`
- Create: `.gitignore`

**Step 1: Create directory structure**

Run:
```bash
mkdir -p cache data
```

Expected: Directories created

**Step 2: Create .gitignore**

Create `.gitignore`:
```gitignore
cache/
data/
```

**Step 3: Create script skeleton with shebang**

Create `fetch-prs.jl`:
```julia
#!/usr/bin/env julia

# PR Fetcher for JuliaRegistries/General
# Fetches manually-merged new package PRs with metadata and comments

using JSON
using Dates

const REPO = "JuliaRegistries/General"
const LABEL = "new package"
const EXCLUDED_MERGERS = ["JuliaTagBot", "jlbuild"]

# File paths
const CACHE_DIR = "cache"
const DATA_DIR = "data"
const PR_LIST_FILE = joinpath(CACHE_DIR, "pr-list.json")
const TO_FETCH_FILE = joinpath(CACHE_DIR, "to-fetch.json")
const PROGRESS_FILE = joinpath(CACHE_DIR, "stage3-progress.json")
const FAILED_FILE = joinpath(CACHE_DIR, "failed.json")

function main()
    println("PR Fetcher starting...")

    # Ensure directories exist
    mkpath(CACHE_DIR)
    mkpath(DATA_DIR)

    # Run stages in sequence (skip if already complete)
    if !isfile(PR_LIST_FILE)
        println("\n=== Stage 1: Fetching PR list ===")
        fetch_pr_list()
    else
        println("\n=== Stage 1: Skipped (pr-list.json exists) ===")
    end

    if !isfile(TO_FETCH_FILE)
        println("\n=== Stage 2: Filtering PRs ===")
        filter_prs()
    else
        println("\n=== Stage 2: Skipped (to-fetch.json exists) ===")
    end

    println("\n=== Stage 3: Fetching PR details ===")
    fetch_details()

    println("\n=== Complete! ===")
end

# Placeholder functions - will implement in later tasks
function fetch_pr_list()
    error("Not implemented")
end

function filter_prs()
    error("Not implemented")
end

function fetch_details()
    error("Not implemented")
end

# Run if executed as script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
```

**Step 4: Make script executable**

Run:
```bash
chmod +x fetch-prs.jl
```

Expected: Script is executable

**Step 5: Test script structure**

Run:
```bash
./fetch-prs.jl
```

Expected: Error "Not implemented" from fetch_pr_list (confirms structure works)

**Step 6: Commit**

```bash
git add .gitignore fetch-prs.jl
git commit -m "feat: add project structure and script skeleton"
```

---

## Task 2: Helper Functions

**Files:**
- Modify: `fetch-prs.jl`

**Step 1: Add rate limit handling helper**

Add after the constants in `fetch-prs.jl`:
```julia
"""Check if gh command output indicates rate limit error"""
function is_rate_limit_error(output::String)
    return occursin("rate limit", lowercase(output)) ||
           occursin("API rate limit exceeded", output)
end

"""Wait until GitHub rate limit resets"""
function wait_for_rate_limit()
    println("Rate limit hit, checking reset time...")

    result = read(`gh api rate_limit`, String)
    data = JSON.parse(result)
    reset_time = data["rate"]["reset"]

    now_unix = Int(floor(datetime2unix(now(UTC))))
    wait_seconds = max(0, reset_time - now_unix)

    if wait_seconds > 0
        reset_dt = unix2datetime(reset_time)
        println("Waiting until $(reset_dt) UTC ($(wait_seconds) seconds)...")
        sleep(wait_seconds + 5)  # Add 5 second buffer
    end
end

"""Execute gh command with retry logic"""
function gh_with_retry(cmd::Cmd; max_retries=5, initial_delay=1.0)
    delay = initial_delay

    for attempt in 1:max_retries
        try
            result = read(cmd, String)
            return result
        catch e
            error_msg = string(e)

            # Check if rate limit error
            if is_rate_limit_error(error_msg)
                wait_for_rate_limit()
                continue  # Retry without counting against limit
            end

            # Last attempt - give up
            if attempt == max_retries
                rethrow(e)
            end

            # Exponential backoff for other errors
            println("Attempt $attempt failed, retrying in $(delay)s: $error_msg")
            sleep(delay)
            delay *= 2
        end
    end
end
```

**Step 2: Add package name parsing helper**

Add after rate limit functions:
```julia
"""Parse package name from PR title"""
function parse_package_name(title::String)
    # Match "New package: PackageName v..." or "New package: PackageName.jl v..."
    m = match(r"New package:\s+(\w+)(?:\.jl)?\s+v", title)
    if m === nothing
        return nothing
    end
    return m.captures[1]
end

"""Get first letter directory for package (uppercase)"""
function get_package_dir(package_name::String)
    first_letter = uppercase(string(package_name[1]))
    return joinpath(DATA_DIR, first_letter)
end

"""Get output file path for PR"""
function get_output_path(package_name::String, pr_number::Int)
    dir = get_package_dir(package_name)
    filename = "$(package_name)-pr$(pr_number).json"
    return joinpath(dir, filename)
end
```

**Step 3: Add failed PR logging helper**

Add after package name functions:
```julia
"""Log failed PR to failed.json"""
function log_failed_pr(pr_number::Int, stage::String, error_type::String, error_message::String)
    # Load existing failures
    failures = if isfile(FAILED_FILE)
        JSON.parsefile(FAILED_FILE)
    else
        []
    end

    # Add new failure
    push!(failures, Dict(
        "pr_number" => pr_number,
        "stage" => stage,
        "error_type" => error_type,
        "error_message" => error_message,
        "timestamp" => string(now(UTC))
    ))

    # Write back
    open(FAILED_FILE, "w") do f
        JSON.print(f, failures, 2)
    end
end
```

**Step 4: Test helper functions**

Add test code at the end of file before `if abspath(PROGRAM_FILE) == @__FILE__`:
```julia
# Quick tests for helpers (remove after testing)
function test_helpers()
    # Test package name parsing
    @assert parse_package_name("New package: Flux v0.1.0") == "Flux"
    @assert parse_package_name("New package: Flux.jl v0.1.0") == "Flux"
    @assert parse_package_name("Something else") === nothing

    # Test directory paths
    @assert get_package_dir("Flux") == "data/F"
    @assert get_output_path("Flux", 123) == "data/F/Flux-pr123.json"

    println("✓ Helper tests passed")
end
```

Run:
```bash
julia -e 'include("fetch-prs.jl"); test_helpers()'
```

Expected: "✓ Helper tests passed"

**Step 5: Remove test code**

Remove the `test_helpers()` function from the file.

**Step 6: Commit**

```bash
git add fetch-prs.jl
git commit -m "feat: add helper functions for retry, parsing, and logging"
```

---

## Task 3: Stage 1 - Fetch PR List via GraphQL

**Files:**
- Modify: `fetch-prs.jl`

**Step 1: Implement GraphQL query construction**

Replace the `fetch_pr_list()` placeholder with:
```julia
function fetch_pr_list()
    println("Fetching PRs from $(REPO) with label '$(LABEL)'...")

    all_prs = []
    has_next_page = true
    cursor = nothing
    page = 0

    while has_next_page
        page += 1
        println("Fetching page $page...")

        # Build GraphQL query
        cursor_arg = cursor === nothing ? "" : ", after: \"$cursor\""
        query = """{
          search(query: "repo:$(REPO) label:\\"$(LABEL)\\" is:merged is:closed", type: ISSUE, first: 100$(cursor_arg)) {
            pageInfo {
              hasNextPage
              endCursor
            }
            nodes {
              ... on PullRequest {
                number
                title
                author { login }
                state
                createdAt
                mergedAt
                mergedBy { login }
              }
            }
          }
        }"""

        # Execute query
        result = gh_with_retry(`gh api graphql -f query=$query`)
        data = JSON.parse(result)

        # Extract PRs
        search_data = data["data"]["search"]
        prs = search_data["nodes"]
        append!(all_prs, prs)

        # Check pagination
        page_info = search_data["pageInfo"]
        has_next_page = page_info["hasNextPage"]
        cursor = page_info["endCursor"]

        println("  Fetched $(length(prs)) PRs ($(length(all_prs)) total)")

        # Small delay between pages
        sleep(0.5)
    end

    # Save to file
    println("\nSaving $(length(all_prs)) PRs to $(PR_LIST_FILE)")
    open(PR_LIST_FILE, "w") do f
        JSON.print(f, all_prs, 2)
    end

    println("✓ Stage 1 complete: $(length(all_prs)) PRs fetched")
end
```

**Step 2: Test Stage 1 (requires gh authentication)**

Run:
```bash
./fetch-prs.jl
```

Expected:
- Fetches multiple pages of PRs
- Creates `cache/pr-list.json`
- Shows count of fetched PRs
- Fails at Stage 2 with "Not implemented"

**Step 3: Verify output format**

Run:
```bash
julia -e 'using JSON; data = JSON.parsefile("cache/pr-list.json"); println("PRs: ", length(data)); println("Sample: ", data[1]["number"], " - ", data[1]["title"])'
```

Expected: Shows PR count and sample PR

**Step 4: Test resumability**

Run:
```bash
./fetch-prs.jl
```

Expected: "Stage 1: Skipped (pr-list.json exists)"

**Step 5: Commit**

```bash
git add fetch-prs.jl
git commit -m "feat: implement Stage 1 - fetch PR list via GraphQL"
```

---

## Task 4: Stage 2 - Filter PRs

**Files:**
- Modify: `fetch-prs.jl`

**Step 1: Implement filter logic**

Replace the `filter_prs()` placeholder with:
```julia
function filter_prs()
    # Load PR list
    println("Loading PR list from $(PR_LIST_FILE)")
    all_prs = JSON.parsefile(PR_LIST_FILE)
    println("Total PRs: $(length(all_prs))")

    # Filter out bot merges
    manual_prs = filter(all_prs) do pr
        merged_by = get(pr, "mergedBy", nothing)
        if merged_by === nothing
            return false  # Not merged, skip
        end
        login = merged_by["login"]
        return !(login in EXCLUDED_MERGERS)
    end
    println("After excluding bots: $(length(manual_prs)) PRs")

    # Filter out already-downloaded PRs and parse failures
    to_fetch = []
    parse_failed = 0
    already_downloaded = 0

    for pr in manual_prs
        # Parse package name
        package_name = parse_package_name(pr["title"])
        if package_name === nothing
            parse_failed += 1
            log_failed_pr(
                pr["number"],
                "parse_package_name",
                "parse_error",
                "Failed to parse package name from title: $(pr["title"])"
            )
            continue
        end

        # Check if already downloaded
        output_path = get_output_path(package_name, pr["number"])
        if isfile(output_path)
            already_downloaded += 1
            continue
        end

        # Add package_name to PR data for Stage 3
        pr["package_name"] = package_name
        push!(to_fetch, pr)
    end

    # Save filtered list
    println("\nFiltered results:")
    println("  Parse failures: $parse_failed")
    println("  Already downloaded: $already_downloaded")
    println("  To fetch: $(length(to_fetch))")

    open(TO_FETCH_FILE, "w") do f
        JSON.print(f, to_fetch, 2)
    end

    println("\n✓ Stage 2 complete: $(length(to_fetch)) PRs to fetch")
end
```

**Step 2: Test Stage 2**

Run:
```bash
rm -f cache/to-fetch.json
./fetch-prs.jl
```

Expected:
- Shows filtering statistics
- Creates `cache/to-fetch.json`
- Shows count of PRs to fetch
- Fails at Stage 3 with "Not implemented"

**Step 3: Verify filtered output**

Run:
```bash
julia -e 'using JSON; data = JSON.parsefile("cache/to-fetch.json"); println("To fetch: ", length(data)); println("Sample: ", data[1]["number"], " - ", data[1]["package_name"])'
```

Expected: Shows filtered count and sample with package_name field

**Step 4: Commit**

```bash
git add fetch-prs.jl
git commit -m "feat: implement Stage 2 - filter PRs by bot and existing files"
```

---

## Task 5: Stage 3 - Fetch PR Details

**Files:**
- Modify: `fetch-prs.jl`

**Step 1: Implement progress tracking helpers**

Add before the `fetch_details()` function:
```julia
"""Load progress file (last completed PR number)"""
function load_progress()
    if !isfile(PROGRESS_FILE)
        return 0
    end
    data = JSON.parsefile(PROGRESS_FILE)
    return get(data, "last_completed_pr", 0)
end

"""Save progress file"""
function save_progress(pr_number::Int)
    open(PROGRESS_FILE, "w") do f
        JSON.print(f, Dict("last_completed_pr" => pr_number), 2)
    end
end
```

**Step 2: Implement PR detail fetching**

Replace the `fetch_details()` placeholder with:
```julia
function fetch_details()
    # Load to-fetch list
    println("Loading PRs to fetch from $(TO_FETCH_FILE)")
    to_fetch = JSON.parsefile(TO_FETCH_FILE)
    println("Total to fetch: $(length(to_fetch))")

    # Load progress
    last_completed = load_progress()
    if last_completed > 0
        println("Resuming from PR #$last_completed")
    end

    # Filter to PRs after last completed
    remaining = filter(pr -> pr["number"] > last_completed, to_fetch)
    println("Remaining to fetch: $(length(remaining))")

    if length(remaining) == 0
        println("✓ Stage 3 complete: All PRs already fetched")
        return
    end

    # Fetch each PR
    fetched = 0
    failed = 0

    for (idx, pr) in enumerate(remaining)
        pr_number = pr["number"]
        package_name = pr["package_name"]

        println("\n[$idx/$(length(remaining))] Fetching PR #$pr_number ($package_name)...")

        try
            # Fetch PR details (body and comments)
            pr_json = gh_with_retry(`gh pr view $pr_number --repo $REPO --json body,comments`)
            pr_details = JSON.parse(pr_json)

            # Fetch review comments
            reviews_json = gh_with_retry(`gh api repos/$REPO/pulls/$pr_number/reviews`)
            reviews = JSON.parse(reviews_json)

            # Build output structure
            output = Dict(
                "pr_number" => pr_number,
                "title" => pr["title"],
                "package_name" => package_name,
                "author" => pr["author"]["login"],
                "state" => pr["state"],
                "created_at" => pr["createdAt"],
                "merged_at" => pr["mergedAt"],
                "merged_by" => pr["mergedBy"]["login"],
                "body" => pr_details["body"],
                "comments" => pr_details["comments"],
                "review_comments" => reviews
            )

            # Write to file
            output_path = get_output_path(package_name, pr_number)
            mkpath(dirname(output_path))

            open(output_path, "w") do f
                JSON.print(f, output, 2)
            end

            # Save progress
            save_progress(pr_number)
            fetched += 1

            println("  ✓ Saved to $output_path")

            # Rate limiting delay
            sleep(0.5)

        catch e
            failed += 1
            error_msg = string(e)
            println("  ✗ Failed: $error_msg")

            log_failed_pr(
                pr_number,
                "fetch_details",
                "fetch_error",
                error_msg
            )
        end
    end

    println("\n✓ Stage 3 complete: $fetched successful, $failed failed")
    if failed > 0
        println("  See $(FAILED_FILE) for details")
    end
end
```

**Step 3: Test Stage 3 (small batch)**

To test without fetching all PRs, temporarily limit the fetch:

Run:
```bash
# Test with just first PR
julia -e '
using JSON
data = JSON.parsefile("cache/to-fetch.json")
open("cache/to-fetch.json", "w") do f
    JSON.print(f, data[1:1], 2)
end
'
rm -f cache/stage3-progress.json
./fetch-prs.jl
```

Expected:
- Fetches 1 PR successfully
- Creates output file in `data/{LETTER}/{PACKAGE}-pr{NUMBER}.json`
- Creates `cache/stage3-progress.json`

**Step 4: Verify output file**

Run:
```bash
find data -name "*.json" -exec head -20 {} \;
```

Expected: Shows JSON with all fields (pr_number, body, comments, etc.)

**Step 5: Test resumability**

Run:
```bash
./fetch-prs.jl
```

Expected: "Remaining to fetch: 0" (already complete)

**Step 6: Restore full to-fetch list**

Run:
```bash
rm -f cache/to-fetch.json cache/stage3-progress.json
```

**Step 7: Commit**

```bash
git add fetch-prs.jl
git commit -m "feat: implement Stage 3 - fetch PR details with progress tracking"
```

---

## Task 6: Command-Line Arguments

**Files:**
- Modify: `fetch-prs.jl`

**Step 1: Add argument parsing**

Replace the `main()` function with:
```julia
function main(args)
    # Parse arguments
    refetch_list = "--refetch-list" in args
    refilter = "--refilter" in args

    if "--help" in args || "-h" in args
        println("""
        Usage: fetch-prs.jl [OPTIONS]

        Fetch manually-merged new package PRs from JuliaRegistries/General.
        Automatically resumes from where it left off.

        Options:
          --refetch-list    Delete cache/pr-list.json and re-fetch from GitHub
          --refilter        Delete cache/to-fetch.json and re-run filtering
          --help, -h        Show this help message

        The script automatically detects which stages are complete and runs
        only the necessary stages.
        """)
        return
    end

    println("PR Fetcher starting...")

    # Ensure directories exist
    mkpath(CACHE_DIR)
    mkpath(DATA_DIR)

    # Handle flags
    if refetch_list
        println("--refetch-list: Removing $(PR_LIST_FILE)")
        rm(PR_LIST_FILE, force=true)
        rm(TO_FETCH_FILE, force=true)  # Also remove dependent file
    end

    if refilter
        println("--refilter: Removing $(TO_FETCH_FILE)")
        rm(TO_FETCH_FILE, force=true)
    end

    # Run stages in sequence (skip if already complete)
    if !isfile(PR_LIST_FILE)
        println("\n=== Stage 1: Fetching PR list ===")
        fetch_pr_list()
    else
        println("\n=== Stage 1: Skipped (pr-list.json exists) ===")
    end

    if !isfile(TO_FETCH_FILE)
        println("\n=== Stage 2: Filtering PRs ===")
        filter_prs()
    else
        println("\n=== Stage 2: Skipped (to-fetch.json exists) ===")
    end

    println("\n=== Stage 3: Fetching PR details ===")
    fetch_details()

    println("\n=== Complete! ===")
end
```

**Step 2: Update script entry point**

Replace the entry point at the bottom with:
```julia
# Run if executed as script
if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
```

**Step 3: Test help flag**

Run:
```bash
./fetch-prs.jl --help
```

Expected: Shows help message

**Step 4: Test refetch flag**

Run:
```bash
./fetch-prs.jl --refetch-list
```

Expected: Re-fetches PR list (may take a while)

**Step 5: Commit**

```bash
git add fetch-prs.jl
git commit -m "feat: add command-line argument parsing"
```

---

## Task 7: Documentation and Final Testing

**Files:**
- Create: `README.md`

**Step 1: Create README**

Create `README.md`:
```markdown
# General Registry PR Fetcher

Fetches manually-merged "new package" PRs from JuliaRegistries/General with full metadata and comments for moderation analysis.

## Prerequisites

- Julia (any recent version)
- GitHub CLI (`gh`) authenticated with your account

## Usage

```bash
./fetch-prs.jl
```

The script automatically:
1. Fetches PR list via GraphQL (Stage 1)
2. Filters out bot merges and existing downloads (Stage 2)
3. Downloads full PR details (Stage 3)

Each stage is resumable - if interrupted, just run again and it picks up where it left off.

### Options

```bash
./fetch-prs.jl --help          # Show help
./fetch-prs.jl --refetch-list  # Re-fetch PR list from scratch
./fetch-prs.jl --refilter      # Re-run filtering stage
```

## Output Structure

```
data/
  A/
    Abc-pr123.json
    Animal-pr1245.json
  B/
    Builds-pr3242.json
  ...
```

Each JSON file contains:
- PR metadata (number, title, author, dates, merger)
- Package name
- Full PR body
- All comments and review comments

## Cache Files

```
cache/
  pr-list.json          # All PRs with "new package" label
  to-fetch.json         # Filtered list to download
  stage3-progress.json  # Last completed PR number
  failed.json           # Failed PRs with error details
```

## Filters

- **Label:** "new package"
- **State:** merged or closed
- **Excludes:** PRs merged by "JuliaTagBot" or "jlbuild" (automated)

## Rate Limiting

The script:
- Adds 0.5s delay between requests
- Automatically waits if GitHub rate limit is hit
- Retries failed requests with exponential backoff (up to 5 times)

## Error Handling

Failed PRs are logged to `cache/failed.json` with error details. The script continues fetching other PRs.

## Expected Runtime

First run fetching all historical PRs: several hours (potentially overnight depending on total count after filtering).
```

**Step 2: Create .gitattributes for LFS (optional)**

If expecting very large data files:

Create `.gitattributes`:
```
data/**/*.json filter=lfs diff=lfs merge=lfs -text
```

Note: Only add this if you plan to commit the data files and they're large.

**Step 3: Full integration test**

Run complete workflow from scratch:
```bash
# Clean all cache and data
rm -rf cache data

# Run full fetch (WARNING: This will take a long time!)
./fetch-prs.jl
```

Expected:
- Completes all 3 stages
- Creates populated data/ directory
- Shows success statistics

**Step 4: Test interruption and resume**

```bash
# Start fetch
./fetch-prs.jl &
FETCH_PID=$!

# Wait a bit then kill it
sleep 10
kill $FETCH_PID

# Resume
./fetch-prs.jl
```

Expected: Resumes from last completed PR

**Step 5: Commit**

```bash
git add README.md .gitattributes
git commit -m "docs: add README and final testing"
```

---

## Task 8: Code Review and Cleanup

**Files:**
- Review: `fetch-prs.jl`, `README.md`

**Step 1: Review code quality**

Check for:
- [ ] All hardcoded values moved to constants
- [ ] Error messages are clear and actionable
- [ ] Functions have reasonable length (<50 lines)
- [ ] No duplicated code
- [ ] Variable names are descriptive

**Step 2: Test error scenarios**

Simulate various failures:
```bash
# Test with invalid gh auth (temporarily)
gh auth logout
./fetch-prs.jl
# Expected: Clear error message about authentication

# Re-authenticate
gh auth login
```

**Step 3: Verify all files are tracked**

Run:
```bash
git status
```

Expected: Only cache/ and data/ should be untracked (in .gitignore)

**Step 4: Final commit**

If any cleanup needed:
```bash
git add -u
git commit -m "refactor: code cleanup and final polish"
```

---

## Completion Checklist

- [ ] Script runs end-to-end successfully
- [ ] All three stages work correctly
- [ ] Resumability works (can Ctrl+C and restart)
- [ ] Rate limiting is handled properly
- [ ] Failed PRs are logged to failed.json
- [ ] Output files have correct structure and data
- [ ] README is clear and complete
- [ ] All code is committed to git

## Next Steps After Implementation

1. Run the full fetch (overnight job)
2. Review `cache/failed.json` for any patterns in failures
3. Spot-check some output JSON files for data quality
4. Consider adding analysis scripts to query the downloaded data

## Notes for Implementer

- The gh CLI must be authenticated before running: `gh auth login`
- First run will take many hours due to the volume of historical PRs
- You can test with a small batch by manually editing `cache/to-fetch.json`
- If you see rate limiting, the script will wait automatically
- The script is idempotent - running multiple times is safe
