#!/usr/bin/env julia --project=.

# Hybrid precedent extraction: Code + LLM via `llm` CLI
# Cheap and flexible - use code where possible, LLM only for hard parts

using JSON
using Dates

# === Code-based extractors (FREE) ===

"""Extract violation type from bot comment"""
function extract_violations(comments)
    violations = []

    # Find the bot comment
    bot_comment = nothing
    for c in comments
        if get(get(c, "author", Dict()), "login", "") == "github-actions" &&
           occursin("AutoMerge Guidelines", get(c, "body", ""))
            bot_comment = get(c, "body", "")
            break
        end
    end

    if bot_comment === nothing
        return violations
    end

    # Extract violations via regex
    if occursin(r"not all letters are upper-case", bot_comment)
        push!(violations, Dict(
            "type" => "all_caps",
            "excerpt" => "not all letters are upper-case"
        ))
    end

    if occursin(r"contains the string \"julia\"", bot_comment)
        push!(violations, Dict(
            "type" => "contains_julia",
            "excerpt" => "contains the string \"julia\""
        ))
    end

    if occursin(r"too short", bot_comment) || occursin(r"(?:must|should) be.*(?:5|five)", bot_comment)
        push!(violations, Dict(
            "type" => "too_short",
            "excerpt" => "name too short"
        ))
    end

    if occursin(r"(?:should|must) start with (?:an )?upper-?case", bot_comment)
        push!(violations, Dict(
            "type" => "lowercase_first",
            "excerpt" => "must start with upper-case"
        ))
    end

    return violations
end

"""Detect if package is a wrapper via keywords"""
function detect_wrapper(body, comments)
    # Check PR body
    body_lower = lowercase(body)
    if occursin(r"wrapper|wraps|wrapping", body_lower)
        # Try to extract library name
        m = match(r"wrapper (?:around|for|of) (?:the )?([A-Za-z0-9_+-]+)", body_lower)
        library = m !== nothing ? m.captures[1] : nothing
        return true, library
    end

    # Check comments
    for c in comments
        text = lowercase(get(c, "body", ""))
        if occursin(r"wrapper|wraps", text)
            return true, nothing
        end
    end

    return false, nothing
end

"""Extract related PR references via regex"""
function find_related_prs(body, comments)
    prs = Int[]

    # Search body
    for m in eachmatch(r"#(\d{4,})", body)
        push!(prs, parse(Int, m.captures[1]))
    end

    # Search comments
    for c in comments
        for m in eachmatch(r"#(\d{4,})", get(c, "body", ""))
            push!(prs, parse(Int, m.captures[1]))
        end
    end

    return unique(prs)
end

"""Check if Slack was mentioned (excluding bot comments)"""
function slack_mentioned(comments)
    for c in comments
        # Skip bot comments
        if get(get(c, "author", Dict()), "login", "") == "github-actions"
            continue
        end

        text = lowercase(get(c, "body", ""))
        if occursin("slack", text) || occursin("#pkg-registration", text)
            return true
        end
    end
    return false
end

"""Calculate days between dates (handles null values)"""
function days_between(created, end_date)
    # Handle null end dates
    if end_date === nothing || isempty(end_date)
        return nothing
    end

    try
        created_dt = DateTime(created[1:19], "yyyy-mm-ddTHH:MM:SS")
        end_dt = DateTime(end_date[1:19], "yyyy-mm-ddTHH:MM:SS")
        return round(Int, (end_dt - created_dt).value / (1000 * 60 * 60 * 24))
    catch e
        @warn "Failed to parse dates" created end_date error=e
        return nothing
    end
end

# === LLM-based extractors (via `llm` CLI) ===

# Track number of LLM calls
const LLM_CALL_COUNT = Ref(0)

"""Call llm CLI with a prompt and schema, return parsed JSON"""
function call_llm(prompt::String, schema::String; model="gemini-2.0-flash-exp")
    try
        # Use llm's --schema feature for guaranteed structured output
        result = readchomp(`llm -m $model --schema $schema $prompt`)
        LLM_CALL_COUNT[] += 1
        return JSON.parse(result)
    catch e
        @warn "LLM call failed" error=e
        return nothing
    end
end

"""Get token usage from llm logs database for the last N calls"""
function get_usage_stats(num_calls::Int)
    try
        # Query the last N log entries as JSON
        logs_json = readchomp(`llm logs -n $num_calls --json`)
        logs = JSON.parse(logs_json)

        # Sum up token usage
        total_input = 0
        total_output = 0

        for log in logs
            total_input += get(log, "input_tokens", 0)
            total_output += get(log, "output_tokens", 0)
        end

        return total_input, total_output
    catch e
        @warn "Failed to get usage stats from llm logs" error=e
        return 0, 0
    end
end

"""Extract package author from PR body"""
function extract_package_author(body::String)
    m = match(r"Created by:.*@(\w+)", body)
    return m !== nothing ? m.captures[1] : nothing
end

"""Classify all comments by their stance on merging"""
function classify_comments(comments, package_name::String, pr_body::String; model="gemini-2.0-flash-exp")
    # Extract package author for context
    package_author = extract_package_author(pr_body)

    # Filter out bot comments (AutoMerge bot)
    human_comments = filter(comments) do c
        author_login = get(get(c, "author", Dict()), "login", "")
        body = get(c, "body", "")

        # Skip bot and very short comments
        author_login != "github-actions" && length(body) > 10
    end

    if isempty(human_comments)
        return []
    end

    # Build structured data for each comment
    comment_data = map(enumerate(human_comments)) do (idx, c)
        author = get(get(c, "author", Dict()), "login", "unknown")

        # Extract reaction counts
        reaction_groups = get(c, "reactionGroups", [])
        reactions = Dict{String, Int}()
        for rg in reaction_groups
            content = get(rg, "content", "")
            count = get(get(rg, "users", Dict()), "totalCount", 0)
            if count > 0
                reactions[content] = count
            end
        end

        Dict(
            "id" => idx,
            "author" => author,
            "author_association" => get(c, "authorAssociation", "NONE"),
            "is_package_author" => (package_author !== nothing && author == package_author),
            "text" => get(c, "body", ""),
            "reactions" => reactions
        )
    end

    author_context = package_author !== nothing ? "\nPackage author: @$package_author" : ""

    prompt = """Classify each comment by its stance on merging THIS SPECIFIC pull request AND rate its influence on the decision.

CONTEXT: This PR proposes to register a package named "$package_name"$author_context

For EACH comment, determine:

STANCE:
- pro_merge: Comment supports/approves merging THIS PR as-is (e.g., "LGTM", "let's merge", "I vote yes", "[noblock]", or argues FOR the proposed name)
- anti_merge: Comment opposes merging THIS PR or raises blocking concerns about the proposed name
- neutral_merge: Comment discusses alternatives or asks questions but doesn't take a clear stance on THIS PR
- unrelated: Comment is off-topic or purely informational

INFLUENCE (1-5 scale):
- 5: Final approval/decision that directly led to merge (e.g., "Let's merge this", maintainer making final call)
- 4: Strong argument that clearly shaped the decision or resolved key concerns
- 3: Meaningful contribution to discussion that influenced thinking
- 2: Minor input, clarification, or suggestion that didn't strongly affect outcome
- 1: Minimal to no impact on the decision (off-topic, purely procedural)

IMPORTANT:
- A comment opposing alternative suggestions is PRO-MERGE if it supports the actual PR name.
- Package author defending their naming choice = pro_merge
- Consider comment timing: later comments closer to merge often have higher influence
- Maintainer (MEMBER) comments generally have higher influence than non-members
- Reactions: Comments with more reactions (especially THUMBS_UP) likely had higher influence on the discussion
- [noblock] tag: This just tells the bot not to block auto-merge. Judge influence based on the comment's actual content, NOT the presence of [noblock]

Comments:
$(JSON.json(comment_data))

Return array of objects with {id: number, stance: "pro_merge"|"anti_merge"|"neutral_merge"|"unrelated", influence: number}"""

    # Schema: array of classification objects
    schema = """{
  "type": "object",
  "properties": {
    "classifications": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "id": {"type": "integer"},
          "stance": {"type": "string", "enum": ["pro_merge", "anti_merge", "neutral_merge", "unrelated"]},
          "influence": {"type": "integer", "minimum": 1, "maximum": 5}
        },
        "required": ["id", "stance", "influence"]
      }
    }
  },
  "required": ["classifications"]
}"""

    result = call_llm(prompt, schema; model=model)
    if result === nothing
        return []
    end

    classifications = get(result, "classifications", [])

    # Check if all comments were classified
    if length(classifications) != length(human_comments)
        @warn "LLM only classified $(length(classifications))/$(length(human_comments)) comments"
    end

    # Merge classifications back with comment data
    classified_comments = []
    unclassified_count = 0

    for (i, comment) in enumerate(human_comments)
        # Find classification for this comment
        classification = nothing
        influence = nothing
        for c in classifications
            if get(c, "id", 0) == i
                classification = get(c, "stance", "unclassified")
                influence = get(c, "influence", nothing)
                break
            end
        end

        if classification === nothing
            classification = "unclassified"
            unclassified_count += 1
        end

        push!(classified_comments, Dict(
            "author" => get(get(comment, "author", Dict()), "login", "unknown"),
            "author_association" => get(comment, "authorAssociation", "NONE"),
            "text" => get(comment, "body", ""),
            "stance" => classification,
            "influence" => influence
        ))
    end

    if unclassified_count > 0
        @warn "$(unclassified_count) comments marked as unclassified"
    end

    return classified_comments
end

"""Extract justification categories using LLM (only for PRs with violations)"""
function extract_justifications(body, comments; model="gemini/gemini-2.0-flash")
    # Build minimal context
    all_text = body * "\n\n" * join([get(c, "body", "") for c in comments], "\n\n")

    # Limit text size (first 3000 chars should be enough)
    if length(all_text) > 3000
        all_text = all_text[1:3000] * "..."
    end

    prompt = """Which justifications are EXPLICITLY MENTIONED or DIRECTLY DISCUSSED in this text?

IMPORTANT: Only select a category if there is clear textual evidence. Do not infer or assume.

Text:
$all_text

Categories (select ONLY if explicitly stated):
- library_wrapper: Text explicitly states package wraps a C/C++/Python/R library (with library name)
- r_package_precedent: Text explicitly cites an R package with similar naming
- python_package_precedent: Text explicitly cites a Python package with similar naming
- domain_specific_acronym: Text explicitly states acronym is well-known in a specific domain
- pronounceable: Text explicitly discusses that the acronym/name is pronounceable
- established_name: Text explicitly states name is already established/known
- core_package: Text explicitly describes package as "core", "infrastructure", or similar
- minimum_length_satisfied: Text explicitly discusses length requirement (5+ chars)
- cli_tool_name: Text explicitly mentions CLI tool/script name matching package name

Return EMPTY ARRAY if no explicit justifications are found. Be conservative."""

    # Schema: array of justification category strings
    schema = """{
  "type": "object",
  "properties": {
    "justifications": {
      "type": "array",
      "items": {
        "type": "string"
      }
    }
  },
  "required": ["justifications"]
}"""

    result = call_llm(prompt, schema; model=model)
    return result === nothing ? [] : get(result, "justifications", [])
end

# === Main extraction ===

function extract_precedent(pr_file::String; model="gemini-2.0-flash-exp")
    println("Extracting precedents from: $pr_file")
    println("Using model: $model")

    pr_data = JSON.parsefile(pr_file)

    # Code-based extraction
    violations = extract_violations(get(pr_data, "comments", []))
    is_wrapper, wrapped_lib = detect_wrapper(get(pr_data, "body", ""), get(pr_data, "comments", []))
    related_prs = find_related_prs(get(pr_data, "body", ""), get(pr_data, "comments", []))
    slack_flag = slack_mentioned(get(pr_data, "comments", []))

    # Determine if PR was merged or just closed
    merged_at = get(pr_data, "merged_at", nothing)
    was_merged = merged_at !== nothing

    # Calculate time to decision (use merged_at if merged, closed_at if just closed)
    decision_date = was_merged ? merged_at : get(pr_data, "closed_at", nothing)
    time_to_decision = days_between(pr_data["created_at"], decision_date)

    # LLM-based extraction (only what we need)
    println("  Classifying comments...")
    classified_comments = classify_comments(
        get(pr_data, "comments", []),
        pr_data["package_name"],
        get(pr_data, "body", "");
        model=model
    )

    justifications = []
    if !isempty(violations)
        println("  Extracting justifications...")
        justifications = extract_justifications(get(pr_data, "body", ""), get(pr_data, "comments", []); model=model)
    end

    # Extract package author
    package_author = extract_package_author(get(pr_data, "body", ""))

    # Build output
    output = Dict(
        "pr_number" => pr_data["pr_number"],
        "package_name" => pr_data["package_name"],
        "package_author" => package_author,
        "violations" => violations,
        "has_violations" => !isempty(violations),
        "wrapper_info" => Dict(
            "is_wrapper" => is_wrapper,
            "wrapped_library" => wrapped_lib
        ),
        "justifications" => justifications,
        "related_prs" => related_prs,
        "slack_mentioned" => slack_flag,
        "decision" => Dict(
            "merged" => was_merged,
            "merged_by" => get(pr_data, "merged_by", nothing),
            "closed_by" => get(pr_data, "closed_by", nothing),
            "time_to_decision_days" => time_to_decision
        ),
        "discussion" => classified_comments,
        "num_comments" => length(get(pr_data, "comments", []))
    )

    return output
end

# === CLI ===

"""Find all PR JSON files in a directory (excluding analysis files)"""
function find_pr_files(dir::String)
    all_files = []
    for (root, dirs, files) in walkdir(dir)
        for file in files
            # Match pattern: *-pr*.json but NOT *-analysis.json
            if occursin(r"-pr\d+\.json$", file) && !occursin("-analysis", file)
                push!(all_files, joinpath(root, file))
            end
        end
    end
    return sort(all_files)
end

"""Convert data/ path to analysis/ path with same structure"""
function get_analysis_path(pr_file::String)
    # Extract the relative path after data/
    if occursin(r"^data/", pr_file) || occursin(r"/data/", pr_file)
        # Replace data/ with analysis/ and add -analysis suffix
        analysis_file = replace(pr_file, r"data/" => "analysis/", count=1)
        analysis_file = replace(analysis_file, r"\.json$" => "-analysis.json")

        # Ensure directory exists
        dir = dirname(analysis_file)
        if !isdir(dir)
            mkpath(dir)
        end

        return analysis_file
    else
        # If not in data/, just add -analysis suffix in same directory
        return replace(pr_file, r"\.json$" => "-analysis.json")
    end
end

function main()
    if length(ARGS) < 1
        println("""
Usage: ./extract-precedents.jl <input> [options]

Extract precedent data from PR JSON file(s).

Arguments:
  input           Path to a PR JSON file OR a directory containing PR JSON files

Options:
  --model MODEL   LLM model to use (default: gemini-2.0-flash-exp)

Examples:
  # Single file
  ./extract-precedents.jl data/J/JuliaC-pr139086.json

  # All files in a directory
  ./extract-precedents.jl data/

  # With custom model
  ./extract-precedents.jl data/ --model claude-3-5-haiku-20241022
""")
        exit(1)
    end

    input_path = ARGS[1]
    model = "gemini-2.0-flash-exp"

    # Parse optional arguments
    i = 2
    while i <= length(ARGS)
        if ARGS[i] == "--model"
            if i + 1 <= length(ARGS)
                model = ARGS[i + 1]
                i += 2
            else
                error("--model requires an argument")
            end
        else
            error("Unknown argument: $(ARGS[i])")
        end
    end

    # Determine if input is a file or directory
    pr_files = []
    if isfile(input_path)
        pr_files = [input_path]
    elseif isdir(input_path)
        pr_files = find_pr_files(input_path)
        if isempty(pr_files)
            error("No PR JSON files found in directory: $input_path")
        end
        println("Found $(length(pr_files)) PR files to process")
        println("Model: $model\n")
    else
        error("Input not found: $input_path")
    end

    # Process all files
    batch_mode = length(pr_files) > 1
    success_count = 0
    error_count = 0

    for (idx, pr_file) in enumerate(pr_files)
        if batch_mode
            println("\n[$idx/$(length(pr_files))] Processing: $pr_file")
            println("=" ^ 70)
        end

        # Extract
        try
            extracted = extract_precedent(pr_file, model=model)

            # Save to analysis/ directory
            output_file = get_analysis_path(pr_file)
            open(output_file, "w") do f
                JSON.print(f, extracted, 2)
            end

            if batch_mode
                println("✓ Saved to: $output_file")
            else
                println("\n✓ Analysis saved to: $output_file")
            end

            # Summary (only show full summary for single file mode)
            if !batch_mode
                println("\n=== Summary ===")
                println("Package: $(extracted["package_name"])")
                println("Violations: $(length(extracted["violations"]))")
                println("Wrapper: $(extracted["wrapper_info"]["is_wrapper"])")
                println("Justifications: $(length(extracted["justifications"]))")
                println("Related PRs: $(length(extracted["related_prs"]))")

                # Comment stance breakdown
                discussion = get(extracted, "discussion", [])
                pro = count(c -> get(c, "stance", "") == "pro_merge", discussion)
                anti = count(c -> get(c, "stance", "") == "anti_merge", discussion)
                neutral = count(c -> get(c, "stance", "") == "neutral_merge", discussion)
                unrelated = count(c -> get(c, "stance", "") == "unrelated", discussion)
                unclassified = count(c -> get(c, "stance", "") == "unclassified", discussion)

                # Influence breakdown
                high_influence = count(c -> get(c, "influence", 0) >= 4, discussion)
                medium_influence = count(c -> get(c, "influence", 0) == 3, discussion)
                low_influence = count(c -> get(c, "influence", 0) <= 2 && get(c, "influence", 0) > 0, discussion)

                if unclassified > 0
                    println("Discussion: $(length(discussion)) comments (pro: $pro, anti: $anti, neutral: $neutral, unrelated: $unrelated, ⚠️  unclassified: $unclassified)")
                else
                    println("Discussion: $(length(discussion)) comments (pro: $pro, anti: $anti, neutral: $neutral, unrelated: $unrelated)")
                end
                println("Influence: high (4-5): $high_influence, medium (3): $medium_influence, low (1-2): $low_influence")

                # Decision info
                decision = extracted["decision"]
                if decision["merged"]
                    println("Decision: MERGED by $(decision["merged_by"]) in $(decision["time_to_decision_days"]) days")
                else
                    closed_by = decision["closed_by"] !== nothing ? decision["closed_by"] : "unknown"
                    days_str = decision["time_to_decision_days"] !== nothing ? "$(decision["time_to_decision_days"]) days" : "unknown time"
                    println("Decision: CLOSED (not merged) by $closed_by in $days_str")
                end
            end

            success_count += 1
        catch e
            error_count += 1
            println("❌ ERROR processing $pr_file:")
            println("  $(sprint(showerror, e))")
            if batch_mode
                println("  Continuing with next file...")
            end
        end
    end

    # Batch summary
    if batch_mode
        println("\n" * "=" ^ 70)
        println("BATCH COMPLETE")
        println("Successfully processed: $success_count/$(length(pr_files))")
        if error_count > 0
            println("Errors: $error_count")
        end
    end

    # Token usage (query from llm logs database)
    if LLM_CALL_COUNT[] > 0
        input_tokens, output_tokens = get_usage_stats(LLM_CALL_COUNT[])

        if input_tokens > 0 || output_tokens > 0
            println("\n=== Token Usage ===")
            println("Input tokens:  $input_tokens")
            println("Output tokens: $output_tokens")
            println("Total tokens:  $(input_tokens + output_tokens)")

            # Cost estimation (prices per 1M tokens)
            # Default to Gemini 2.0 Flash pricing
            cost_per_input = 0.10  # per 1M tokens
            cost_per_output = 0.40  # per 1M tokens

            input_cost = (input_tokens / 1_000_000) * cost_per_input
            output_cost = (output_tokens / 1_000_000) * cost_per_output
            total_cost = input_cost + output_cost

            println("Estimated cost: \$$(round(total_cost, digits=6))")
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
