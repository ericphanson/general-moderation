#!/usr/bin/env julia --project=.

# Extract moderation precedents from PR using Claude API

using JSON
using HTTP
using Dates

const ANTHROPIC_API_KEY = get(ENV, "ANTHROPIC_API_KEY", "")

function call_claude(prompt::String, system::String="")
    if isempty(ANTHROPIC_API_KEY)
        error("ANTHROPIC_API_KEY environment variable not set")
    end

    headers = [
        "x-api-key" => ANTHROPIC_API_KEY,
        "anthropic-version" => "2023-06-01",
        "content-type" => "application/json"
    ]

    body = Dict(
        "model" => "claude-sonnet-4-20250514",
        "max_tokens" => 8192,
        "messages" => [
            Dict("role" => "user", "content" => prompt)
        ]
    )

    if !isempty(system)
        body["system"] = system
    end

    response = HTTP.post(
        "https://api.anthropic.com/v1/messages",
        headers,
        JSON.json(body)
    )

    result = JSON.parse(String(response.body))
    return result["content"][1]["text"]
end

"""Extract JSON from LLM response, handling markdown code blocks"""
function extract_json(response::String)
    # Try to find JSON in markdown code block
    m = match(r"```(?:json)?\s*\n(.*?)\n```"s, response)
    if m !== nothing
        return JSON.parse(m.captures[1])
    end

    # Try to parse entire response as JSON
    try
        return JSON.parse(response)
    catch
        # Last resort: find first { and last }
        start_idx = findfirst('{', response)
        end_idx = findlast('}', response)
        if start_idx !== nothing && end_idx !== nothing
            return JSON.parse(response[start_idx:end_idx])
        end
        error("Could not extract JSON from response")
    end
end

"""Calculate days between two ISO 8601 datetime strings"""
function days_between(created::String, merged::String)
    created_dt = DateTime(created[1:19], "yyyy-mm-ddTHH:MM:SS")
    merged_dt = DateTime(merged[1:19], "yyyy-mm-ddTHH:MM:SS")
    return round(Int, (merged_dt - created_dt).value / (1000 * 60 * 60 * 24))
end

function extract_precedent(pr_file::String)
    println("Extracting precedents from: $pr_file")

    # Load PR data
    pr_data = JSON.parsefile(pr_file)

    # Calculate time to merge
    time_to_merge = days_between(pr_data["created_at"], pr_data["merged_at"])

    # Build extraction prompt
    system_prompt = """You are analyzing package registration decisions to build a moderation precedent database.

Focus on EXTRACTING FACTS, not inferring intent:
- Quote exact text when available
- Mark fields as null when information is absent
- For "strength" ratings, base on: 1) number of supporters, 2) maintainer vs user, 3) presence of precedent citations
- For "consensus_level":
  * unanimous = all participants agree
  * majority = >50% agree
  * split = mixed opinions
  * single_approver = merged without discussion
- Comments marked [noblock] do NOT block the PR, but may contain important justifications
- Only count discussion that influences the manual merge decision

Extract moderation precedents following this exact JSON schema:

{
  "violations": [
    {
      "type": "enum[all_caps, too_short, contains_julia, lowercase_first, name_similarity, too_generic, ambiguous, other]",
      "bot_message_excerpt": "brief excerpt from AutoMerge bot explaining the violation",
      "severity": "enum[blocking, warning]"
    }
  ],
  "wrapper_info": {
    "is_wrapper": boolean,
    "wrapped_library": "name of wrapped library if wrapper, else null",
    "wrapper_language": "C, C++, Python, R, etc. or null"
  },
  "acronym_info": {
    "is_acronym": boolean,
    "acronym_expansion": "full expansion if acronym, else null",
    "is_well_known": boolean,
    "is_pronounceable": boolean
  },
  "justifications": [
    {
      "category": "enum[library_wrapper, r_package_precedent, python_package_precedent, domain_specific_acronym, generic_acronym, brand_name, established_name, consistency, author_preference, core_package, minimum_length_satisfied, cli_tool_name, pronounceable, other]",
      "reasoning": "brief summary of argument",
      "provided_by": "username",
      "strength": "enum[strong, moderate, weak]"
    }
  ],
  "decision": {
    "outcome": "enum[approved, rejected, renamed, approved_with_conditions, redirected_to_slack]",
    "final_name": "package name",
    "merged_by": "username",
    "time_to_merge_days": ${time_to_merge},
    "rationale_summary": "1-2 sentence summary of why approved/rejected"
  },
  "precedents_cited": [
    {
      "type": "enum[package_name, pr_number, guideline_exception, naming_pattern, r_package, python_package]",
      "reference": "specific citation (e.g., 'SLOPE R package', 'PR #133795')",
      "purpose": "why it was cited"
    }
  ],
  "related_prs": [pr_numbers as integers],
  "slack_mentioned": boolean,
  "alternatives_discussed": ["alternative names suggested"],
  "key_principles": ["extracted principles that could serve as precedents"],
  "conditional_approval": {
    "is_conditional": boolean,
    "conditions": ["e.g., 'does not set precedent for others'"]
  },
  "community_dynamics": {
    "discussion_length": number_of_comments,
    "num_members_involved": number,
    "consensus_level": "enum[unanimous, majority, split, single_approver]",
    "notable_quotes": ["1-2 key quotes from MAINTAINERS that could serve as precedents. Focus on statements about rules, not author justifications."]
  },
  "meta_commentary": {
    "standards_evolution_mentioned": boolean,
    "anti_precedent_disclaimer": boolean,
    "wrapper_exception_invoked": boolean,
    "bot_rule_criticism": boolean
  },
  "extraction_confidence": "enum[high, medium, low]",
  "ambiguous_fields": ["field names where information was uncertain or incomplete"]
}

Be precise. Extract actual quotes for notable_quotes. If information is missing, use null."""

    user_prompt = """Analyze this Julia package registration PR and extract structured precedent information.

PR Data:
$(JSON.json(pr_data, 2))

First, briefly identify:
1. What naming violations were flagged by the bot?
2. What justifications were provided by the author/community?
3. What was the final decision and who made it?
4. Were any precedents or related PRs cited?
5. What are 1-2 key maintainer quotes that establish precedents?

Then, return valid JSON matching the schema. You may include your analysis, then output the JSON in a markdown code block like:

```json
{
  "violations": [...],
  ...
}
```"""

    # Call Claude
    response = call_claude(user_prompt, system_prompt)

    # Extract and parse JSON from response
    extracted = extract_json(response)

    return extracted
end

function main()
    if length(ARGS) < 1
        println("Usage: ./extract-precedents.jl <pr-json-file>")
        println("Example: ./extract-precedents.jl data/J/JuliaC-pr139086.json")
        exit(1)
    end

    pr_file = ARGS[1]

    if !isfile(pr_file)
        error("File not found: $pr_file")
    end

    # Extract precedent
    extracted = extract_precedent(pr_file)

    # Save output
    output_file = replace(pr_file, r"\.json$" => "-analysis.json")
    open(output_file, "w") do f
        JSON.print(f, extracted, 2)
    end

    println("\n✓ Analysis saved to: $output_file")

    # Print summary
    println("\n=== Summary ===")
    println("Violations: $(length(get(extracted, "violations", [])))")
    println("Outcome: $(get(get(extracted, "decision", Dict()), "outcome", "unknown"))")
    println("Final name: $(get(get(extracted, "decision", Dict()), "final_name", "unknown"))")
    println("Extraction confidence: $(get(extracted, "extraction_confidence", "unknown"))")

    if get(get(extracted, "wrapper_info", Dict()), "is_wrapper", false)
        println("🔗 Wrapper for: $(get(get(extracted, "wrapper_info", Dict()), "wrapped_library", "unknown"))")
    end

    if get(get(extracted, "conditional_approval", Dict()), "is_conditional", false)
        conditions = get(get(extracted, "conditional_approval", Dict()), "conditions", [])
        println("⚠️  Conditional approval with: $(conditions)")
    end

    key_principles = get(extracted, "key_principles", [])
    if !isempty(key_principles)
        println("\nKey principles:")
        for principle in key_principles
            println("  - $principle")
        end
    end

    ambiguous_fields = get(extracted, "ambiguous_fields", [])
    if !isempty(ambiguous_fields)
        println("\n⚠️  Ambiguous fields: $(join(ambiguous_fields, ", "))")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
