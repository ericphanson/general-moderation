#!/usr/bin/env julia --project=.

using JSON
using Dates

"""Count token usage from llm logs over the last N days"""
function count_tokens(days::Int=3; max_logs::Int=10000)
    println("Fetching last $max_logs log entries...")

    # Fetch logs as JSON
    logs_json = readchomp(`llm logs -n $max_logs --json`)
    logs = JSON.parse(logs_json)

    println("Found $(length(logs)) log entries")

    # Calculate cutoff date
    cutoff = now(UTC) - Day(days)
    println("Filtering for entries after: $cutoff")

    # Filter and sum
    total_input = 0
    total_output = 0
    filtered_count = 0

    # Track by model
    model_stats = Dict{String, Dict{String,Int}}()

    for log in logs
        # Parse datetime
        datetime_str = get(log, "datetime_utc", "")
        if isempty(datetime_str)
            continue
        end

        try
            # Parse datetime (format: "2025-11-12T14:19:50.103443+00:00")
            dt = DateTime(datetime_str[1:19], "yyyy-mm-ddTHH:MM:SS")

            # Skip if too old
            if dt < cutoff
                continue
            end

            # Count tokens
            input = get(log, "input_tokens", 0)
            output = get(log, "output_tokens", 0)

            total_input += input
            total_output += output
            filtered_count += 1

            # Track by model
            model = get(log, "model", "unknown")
            if !haskey(model_stats, model)
                model_stats[model] = Dict("input" => 0, "output" => 0, "count" => 0)
            end
            model_stats[model]["input"] += input
            model_stats[model]["output"] += output
            model_stats[model]["count"] += 1
        catch e
            @warn "Failed to parse log entry" error=e
        end
    end

    println("\n" * "="^70)
    println("TOKEN USAGE - Last $days days")
    println("="^70)
    println("Filtered entries: $filtered_count")
    println("\nTotal:")
    println("  Input tokens:  $(format_number(total_input))")
    println("  Output tokens: $(format_number(total_output))")
    println("  Total tokens:  $(format_number(total_input + total_output))")

    # Estimate cost (Gemini 2.0 Flash pricing by default)
    cost_per_input = 0.10  # per 1M tokens
    cost_per_output = 0.40  # per 1M tokens

    input_cost = (total_input / 1_000_000) * cost_per_input
    output_cost = (total_output / 1_000_000) * cost_per_output
    total_cost = input_cost + output_cost

    println("\nEstimated cost: \$$(round(total_cost, digits=4))")
    println("  (assuming Gemini 2.0 Flash pricing)")

    # Breakdown by model
    if !isempty(model_stats)
        println("\n" * "="^70)
        println("BREAKDOWN BY MODEL")
        println("="^70)
        for (model, stats) in sort(collect(model_stats), by=x->x[2]["count"], rev=true)
            input = stats["input"]
            output = stats["output"]
            count = stats["count"]
            total = input + output

            println("\n$model:")
            println("  Calls:  $count")
            println("  Input:  $(format_number(input))")
            println("  Output: $(format_number(output))")
            println("  Total:  $(format_number(total))")

            # Model-specific cost estimates
            if occursin("gemini", lowercase(model))
                cost = (input / 1_000_000) * 0.10 + (output / 1_000_000) * 0.40
                println("  Cost:   \$$(round(cost, digits=4))")
            elseif occursin("claude", lowercase(model))
                # Claude 3.5 Haiku pricing
                cost = (input / 1_000_000) * 1.00 + (output / 1_000_000) * 5.00
                println("  Cost:   ~\$$(round(cost, digits=4)) (Haiku pricing)")
            end
        end
    end

    println("\n" * "="^70)
end

"""Format number with thousand separators"""
function format_number(n::Int)
    s = string(n)
    # Add commas
    result = ""
    for (i, c) in enumerate(reverse(s))
        if i > 1 && (i - 1) % 3 == 0
            result = "," * result
        end
        result = c * result
    end
    return result
end

# Parse command line arguments
if length(ARGS) > 0
    days = parse(Int, ARGS[1])
else
    days = 3
end

if length(ARGS) > 1
    max_logs = parse(Int, ARGS[2])
else
    max_logs = 10000
end

count_tokens(days, max_logs=max_logs)
