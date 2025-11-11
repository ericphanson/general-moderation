#!/usr/bin/env -S julia --project=.

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
