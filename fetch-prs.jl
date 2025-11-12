#!/usr/bin/env -S julia --project=.

# PR Fetcher for JuliaRegistries/General
# Fetches manually-merged new package PRs with metadata and comments

using JSON
using Dates

const REPO = "JuliaRegistries/General"
const LABEL = "new package"
const EXCLUDED_MERGERS = ["JuliaTagBot", "jlbuild", "github-actions[bot]"]

# File paths
const CACHE_DIR = "cache"
const DATA_DIR = "data"
const PR_LIST_FILE = joinpath(CACHE_DIR, "pr-list.json")
const PR_LIST_COMPLETE = joinpath(CACHE_DIR, "pr-list-complete.marker")
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
    # Match various formats:
    # - "New package: PackageName"
    # - "Register PackageName: version"
    # - "Register New Package PackageName: version"
    m = match(r"(?:New package|Register(?:\s+New\s+Package)?):\s+(\w+)|Register\s+(\w+):", title)
    if m === nothing
        return nothing
    end
    # Return first non-nothing capture
    return something(m.captures[1], m.captures[2])
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
    println("Using REST API with cursor-based pagination (this may take a while)...")

    # Check for existing PRs if resuming
    existing_pr_numbers = Set{Int}()
    pr_count = 0
    if isfile(PR_LIST_FILE)
        open(PR_LIST_FILE, "r") do f
            for line in eachline(f)
                pr_data = JSON.parse(line)
                push!(existing_pr_numbers, pr_data["number"])
                pr_count += 1
            end
        end
        println("Found $(pr_count) existing PRs, will skip duplicates")
    end

    # Fetch all issues with label using --paginate (handles cursor-based pagination)
    println("Fetching all issues with label '$(LABEL)'...")
    label_param = replace(LABEL, " " => "%20")
    result = gh_with_retry(`gh api --paginate "repos/$(REPO)/issues?state=closed&labels=$(label_param)&per_page=100"`)

    # Parse all issues (gh --paginate returns JSON array)
    all_issues = JSON.parse(result)
    println("Fetched $(length(all_issues)) total issues")

    # Filter to only PRs
    all_prs = filter(issue -> haskey(issue, "pull_request"), all_issues)
    println("Found $(length(all_prs)) PRs")

    # Fetch PR details for each (with mergedBy info)
    new_fetched = 0
    open(PR_LIST_FILE, "a") do f
        for (idx, issue) in enumerate(all_prs)
            pr_number = issue["number"]

            # Skip if already fetched
            if pr_number in existing_pr_numbers
                continue
            end

            # Progress indicator
            if idx % 100 == 0
                println("Processing PR $idx/$(length(all_prs))...")
            end

            # Fetch PR details to get merge info
            pr_details_json = gh_with_retry(`gh api "repos/$(REPO)/pulls/$(pr_number)"`)
            pr_details = JSON.parse(pr_details_json)

            # Build PR record with merge info and close info
            pr = Dict(
                "number" => pr_number,
                "title" => issue["title"],
                "author" => Dict("login" => issue["user"]["login"]),
                "state" => pr_details["state"],
                "createdAt" => issue["created_at"],
                "closedAt" => issue["closed_at"],
                "closedBy" => if issue["closed_by"] !== nothing
                    Dict("login" => issue["closed_by"]["login"])
                else
                    nothing
                end,
                "mergedAt" => get(pr_details, "merged_at", nothing),
                "mergedBy" => if get(pr_details, "merged_at", nothing) !== nothing && haskey(pr_details, "merged_by") && pr_details["merged_by"] !== nothing
                    Dict("login" => pr_details["merged_by"]["login"])
                else
                    nothing
                end
            )
            println(f, JSON.json(pr))
            new_fetched += 1

            # Rate limiting delay
            sleep(0.5)
        end
    end

    pr_count += new_fetched
    println("\n✓ Stage 1 complete: $(pr_count) total PRs ($(new_fetched) newly fetched)")

    # Mark as complete
    open(PR_LIST_COMPLETE, "w") do f
        write(f, "$(pr_count) PRs fetched at $(now(UTC))")
    end
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

    # Filter out bot merges and bot closes
    manual_prs = filter(all_prs) do pr
        # Check if manually merged
        merged_by = get(pr, "mergedBy", nothing)
        if merged_by !== nothing
            login = merged_by["login"]
            return !(login in EXCLUDED_MERGERS)
        end

        # Check if manually closed (not merged)
        closed_by = get(pr, "closedBy", nothing)
        if closed_by !== nothing
            login = closed_by["login"]
            return !(login in EXCLUDED_MERGERS)
        end

        # Neither merged nor closed by anyone (shouldn't happen for closed PRs)
        return false
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

    # # Filter to PRs after last completed
    # remaining = filter(pr -> pr["number"] <= last_completed, to_fetch)
    # println("Remaining to fetch: $(length(remaining))")

    # if length(remaining) == 0
    #     println("✓ Stage 3 complete: All PRs already fetched")
    #     return
    # end
    remaining = to_fetch

    # Fetch each PR
    fetched = 0
    failed = 0

    for (idx, pr) in enumerate(remaining)
        pr_number = pr["number"]
        package_name = pr["package_name"]

        output_path = get_output_path(package_name, pr_number)
        isfile(output_path) && continue

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
                "closed_at" => pr["closedAt"],
                "closed_by" => if pr["closedBy"] !== nothing
                    pr["closedBy"]["login"]
                else
                    nothing
                end,
                "merged_at" => pr["mergedAt"],
                "merged_by" => if pr["mergedBy"] !== nothing
                    pr["mergedBy"]["login"]
                else
                    nothing
                end,
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
