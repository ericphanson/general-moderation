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
