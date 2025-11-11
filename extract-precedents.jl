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

"""Check if Slack was mentioned"""
function slack_mentioned(comments)
    for c in comments
        text = lowercase(get(c, "body", ""))
        if occursin("slack", text) || occursin("#pkg-registration", text)
            return true
        end
    end
    return false
end

"""Calculate days between dates"""
function days_between(created::String, merged::String)
    created_dt = DateTime(created[1:19], "yyyy-mm-ddTHH:MM:SS")
    merged_dt = DateTime(merged[1:19], "yyyy-mm-ddTHH:MM:SS")
    return round(Int, (merged_dt - created_dt).value / (1000 * 60 * 60 * 24))
end

# === LLM-based extractors (via `llm` CLI) ===

"""Call llm CLI with a prompt and schema, return parsed JSON"""
function call_llm(prompt::String, schema::String; model="gemini-2.0-flash-exp")
    try
        # Use llm's --schema feature for guaranteed structured output
        # Julia's Cmd handles escaping automatically
        result = readchomp(`llm -m $model --schema $schema $prompt`)
        return JSON.parse(result)
    catch e
        @warn "LLM call failed" error=e
        return nothing
    end
end

"""Extract maintainer quotes using LLM"""
function extract_quotes(comments)
    # Filter to maintainer comments only (not bot, not [noblock] only comments)
    maintainer_comments = filter(comments) do c
        assoc = get(c, "authorAssociation", "NONE")
        body = get(c, "body", "")

        # Must be maintainer, not just "[noblock]", not bot message
        assoc == "MEMBER" &&
        !startswith(body, "Hello, I am") &&
        length(body) > 20  # Skip very short comments
    end

    if isempty(maintainer_comments)
        return []
    end

    # Build minimal JSON for LLM
    minimal = map(maintainer_comments) do c
        Dict(
            "author" => get(get(c, "author", Dict()), "login", "unknown"),
            "text" => get(c, "body", "")
        )
    end

    prompt = """Find 1-2 key quotes from these maintainer comments that explain the decision or set precedents.
Focus on statements about rules/guidelines, not author justifications.

Comments:
$(JSON.json(minimal))

If no significant quotes, return empty array."""

    # Schema: array of quote strings
    schema = "quotes: array of quote strings"

    result = call_llm(prompt, schema)
    return result === nothing ? [] : get(result, "quotes", [])
end

"""Extract justification categories using LLM (only for PRs with violations)"""
function extract_justifications(body, comments)
    # Build minimal context
    all_text = body * "\n\n" * join([get(c, "body", "") for c in comments], "\n\n")

    # Limit text size (first 3000 chars should be enough)
    if length(all_text) > 3000
        all_text = all_text[1:3000] * "..."
    end

    prompt = """What justifications were provided for this package name? Select all that apply:

Text:
$all_text

Categories:
- library_wrapper: Package wraps an existing C/C++/Python/R library
- r_package_precedent: Cites R package with similar name
- python_package_precedent: Cites Python package with similar name
- domain_specific_acronym: Acronym is well-known in specific domain
- pronounceable: Acronym is pronounceable
- established_name: Name is already established/well-known
- core_package: Core Julia infrastructure package
- minimum_length_satisfied: Long enough (5+ chars) even if acronym
- cli_tool_name: Package provides CLI tool with this name"""

    # Schema: array of justification category strings
    schema = "justifications: array of justification categories"

    result = call_llm(prompt, schema)
    return result === nothing ? [] : get(result, "justifications", [])
end

# === Main extraction ===

function extract_precedent(pr_file::String)
    println("Extracting precedents from: $pr_file")

    pr_data = JSON.parsefile(pr_file)

    # Code-based extraction
    violations = extract_violations(get(pr_data, "comments", []))
    is_wrapper, wrapped_lib = detect_wrapper(get(pr_data, "body", ""), get(pr_data, "comments", []))
    related_prs = find_related_prs(get(pr_data, "body", ""), get(pr_data, "comments", []))
    slack_flag = slack_mentioned(get(pr_data, "comments", []))
    time_to_merge = days_between(pr_data["created_at"], pr_data["merged_at"])

    # LLM-based extraction (only what we need)
    println("  Extracting quotes...")
    quotes = extract_quotes(get(pr_data, "comments", []))

    justifications = []
    if !isempty(violations)
        println("  Extracting justifications...")
        justifications = extract_justifications(get(pr_data, "body", ""), get(pr_data, "comments", []))
    end

    # Build output
    output = Dict(
        "pr_number" => pr_data["pr_number"],
        "package_name" => pr_data["package_name"],
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
            "merged_by" => pr_data["merged_by"],
            "time_to_merge_days" => time_to_merge
        ),
        "maintainer_quotes" => quotes,
        "num_comments" => length(get(pr_data, "comments", []))
    )

    return output
end

# === CLI ===

function main()
    if length(ARGS) < 1
        println("""
Usage: ./extract-precedents.jl <pr-json-file> [options]

Options:
  --model MODEL    LLM model to use (default: gemini-2.0-flash-exp)

Examples:
  ./extract-precedents.jl data/J/JuliaC-pr139086.json
  ./extract-precedents.jl data/S/SLOPE-pr131898.json --model claude-3-5-haiku-20241022
""")
        exit(1)
    end

    pr_file = ARGS[1]

    if !isfile(pr_file)
        error("File not found: $pr_file")
    end

    # Extract
    extracted = extract_precedent(pr_file)

    # Save
    output_file = replace(pr_file, r"\.json$" => "-analysis.json")
    open(output_file, "w") do f
        JSON.print(f, extracted, 2)
    end

    println("\n✓ Analysis saved to: $output_file")

    # Summary
    println("\n=== Summary ===")
    println("Package: $(extracted["package_name"])")
    println("Violations: $(length(extracted["violations"]))")
    println("Wrapper: $(extracted["wrapper_info"]["is_wrapper"])")
    println("Justifications: $(length(extracted["justifications"]))")
    println("Related PRs: $(length(extracted["related_prs"]))")
    println("Maintainer quotes: $(length(extracted["maintainer_quotes"]))")
    println("Time to merge: $(extracted["decision"]["time_to_merge_days"]) days")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
