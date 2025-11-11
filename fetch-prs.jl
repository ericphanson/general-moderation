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
const PR_LIST_COMPLETE = joinpath(CACHE_DIR, "pr-list-complete.marker")
const PR_LIST_PROGRESS = joinpath(CACHE_DIR, "pr-list-progress.json")
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
    if !isfile(PR_LIST_COMPLETE)
        println("\n=== Stage 1: Fetching PR list ===")
        fetch_pr_list()
    else
        println("\n=== Stage 1: Skipped (complete marker exists) ===")
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

function fetch_pr_list()
    println("Fetching PRs from $(REPO) with label '$(LABEL)'...")
    println("Using REST API with full pagination (this may take a while)...")

    # Count existing PRs if resuming (JSONLines format - one JSON per line)
    pr_count = if isfile(PR_LIST_FILE)
        count = countlines(PR_LIST_FILE)
        println("Resuming: $(count) PRs already fetched")
        count
    else
        0
    end

    # Load last page number if resuming
    start_page = if isfile(PR_LIST_PROGRESS)
        progress = JSON.parsefile(PR_LIST_PROGRESS)
        last_page = get(progress, "last_page", 0)
        println("Resuming from page $(last_page + 1)")
        last_page
    else
        0
    end

    page = start_page
    per_page = 100
    page_fetched_count = 0

    while true
        page += 1
        println("Fetching page $page...")

        # Fetch issues with label filter (PRs are also issues)
        # Note: URL encoding spaces as %20
        label_param = replace(LABEL, " " => "%20")
        result = gh_with_retry(`gh api "repos/$(REPO)/issues?state=closed&labels=$(label_param)&per_page=$(per_page)&page=$(page)"`)
        issues = JSON.parse(result)

        # Check if we got any results
        if length(issues) == 0
            println("  No more results")
            break
        end

        # Filter to only PRs (issues have a pull_request field)
        page_prs = filter(issue -> haskey(issue, "pull_request"), issues)

        # Fetch PR details for each to get mergedBy info
        open(PR_LIST_FILE, "a") do f
            for issue in page_prs
                pr_number = issue["number"]

                # Fetch PR details to get merge info
                pr_details_json = gh_with_retry(`gh api "repos/$(REPO)/pulls/$(pr_number)"`)
                pr_details = JSON.parse(pr_details_json)

                # Build PR record with merge info
                pr = Dict(
                    "number" => pr_number,
                    "title" => issue["title"],
                    "author" => Dict("login" => issue["user"]["login"]),
                    "state" => pr_details["state"],
                    "createdAt" => issue["created_at"],
                    "mergedAt" => get(pr_details, "merged_at", nothing),
                    "mergedBy" => if get(pr_details, "merged_at", nothing) !== nothing && haskey(pr_details, "merged_by") && pr_details["merged_by"] !== nothing
                        Dict("login" => pr_details["merged_by"]["login"])
                    else
                        nothing
                    end
                )
                println(f, JSON.json(pr))
                page_fetched_count += 1
            end
        end

        pr_count += length(page_prs)
        println("  Fetched $(length(page_prs)) PRs from $(length(issues)) issues ($(pr_count) total PRs)")

        # Save progress
        open(PR_LIST_PROGRESS, "w") do f
            JSON.print(f, Dict("last_page" => page), 2)
        end

        # If we got fewer than per_page, we're done
        if length(issues) < per_page
            println("  Last page reached")
            break
        end

        # Small delay between pages to be nice to API
        sleep(0.5)
    end

    # Mark as complete
    open(PR_LIST_COMPLETE, "w") do f
        write(f, "$(pr_count) PRs fetched at $(now(UTC))")
    end

    println("\n✓ Stage 1 complete: $(pr_count) PRs fetched")
end

function filter_prs()
    # Load PR list from JSONLines file
    println("Loading PR list from $(PR_LIST_FILE)")
    all_prs = []
    open(PR_LIST_FILE, "r") do f
        for line in eachline(f)
            push!(all_prs, JSON.parse(line))
        end
    end
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

        # Convert to String (parse_package_name returns SubString)
        package_name = String(package_name)

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

# Run if executed as script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
