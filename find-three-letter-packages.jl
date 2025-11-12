#!/usr/bin/env julia --project=.

using JSON
using Dates

"""Find all PR JSON files in data/ directory"""
function find_all_pr_files(dir="data")
    files = []
    for (root, _, filenames) in walkdir(dir)
        for file in filenames
            # Match pattern: *-pr*.json but NOT *-analysis.json
            if occursin(r"-pr\d+\.json$", file) && !occursin("-analysis", file)
                push!(files, joinpath(root, file))
            end
        end
    end
    return sort(files)
end

"""Check if analysis file exists for a PR file"""
function get_analysis_path(pr_file::String)
    # Replace data/ with analysis/ and add -analysis suffix
    analysis_file = replace(pr_file, r"data/" => "analysis/", count=1)
    analysis_file = replace(analysis_file, r"\.json$" => "-analysis.json")
    return analysis_file
end

"""Extract package name from PR data"""
function get_package_info(pr_file::String)
    try
        data = JSON.parsefile(pr_file)
        package_name = get(data, "package_name", "unknown")
        pr_number = get(data, "pr_number", "unknown")
        merged = get(data, "merged_at", nothing) !== nothing
        merged_by = get(data, "merged_by", nothing)
        num_comments = length(get(data, "comments", []))
        return (package_name, pr_number, merged, merged_by, num_comments)
    catch e
        @warn "Failed to read $pr_file" error=e
        return (nothing, nothing, nothing, nothing, nothing)
    end
end

"""Get most influential non-bot non-author comment from analysis"""
function get_influential_comment(analysis_file::String, package_author::String)
    try
        if !isfile(analysis_file)
            return nothing
        end

        data = JSON.parsefile(analysis_file)
        discussion = get(data, "discussion", [])

        # Filter out bot comments and author comments
        filtered = filter(discussion) do entry
            author = get(entry, "author", "")
            # Exclude bot and the package author
            author != "github-actions" && author != package_author
        end

        if isempty(filtered)
            return nothing
        end

        # Find highest influence
        most_influential = sort(filtered, by=e -> get(e, "influence", 0), rev=true)[1]

        return Dict(
            "author" => get(most_influential, "author", "unknown"),
            "influence" => get(most_influential, "influence", 0),
            "text" => get(most_influential, "text", "")
        )
    catch e
        return nothing
    end
end

"""Main function to find 3-letter packages"""
function main()
    println("Finding all PR files in data/...")
    pr_files = find_all_pr_files()
    println("Found $(length(pr_files)) PR files\n")

    println("Filtering for 3-letter package names...")
    three_letter_packages = []

    for pr_file in pr_files
        package_name, pr_number, merged, merged_by, num_comments = get_package_info(pr_file)

        if package_name === nothing
            continue
        end

        # Check if package name is exactly 3 letters (excluding .jl suffix and _jll suffix)
        base_name = replace(package_name, r"\.jl$" => "")
        base_name = replace(base_name, r"_jll$" => "")

        if length(base_name) == 3
            analysis_file = get_analysis_path(pr_file)
            has_analysis = isfile(analysis_file)

            # Get package author and influential comment from analysis
            package_author = ""
            influential_comment = nothing
            if has_analysis
                try
                    analysis_data = JSON.parsefile(analysis_file)
                    package_author = get(analysis_data, "package_author", "")
                    influential_comment = get_influential_comment(analysis_file, package_author)
                catch
                end
            end

            push!(three_letter_packages, Dict(
                "package_name" => package_name,
                "pr_number" => pr_number,
                "merged" => merged,
                "merged_by" => merged_by,
                "num_comments" => num_comments,
                "pr_file" => pr_file,
                "analysis_file" => analysis_file,
                "has_analysis" => has_analysis,
                "package_author" => package_author,
                "influential_comment" => influential_comment
            ))
        end
    end

    println("Found $(length(three_letter_packages)) packages with 3-letter names\n")

    # Sort by package name
    sort!(three_letter_packages, by=x -> x["package_name"])

    # Generate markdown report
    println("Generating markdown report...")

    report = """
# Three-Letter Package Names in Julia Registry

**Generated:** $(Dates.now())
**Total 3-letter packages found:** $(length(three_letter_packages))

## Summary

- **Merged:** $(count(p -> p["merged"], three_letter_packages))
- **Not merged (closed):** $(count(p -> !p["merged"], three_letter_packages))
- **With analysis:** $(count(p -> p["has_analysis"], three_letter_packages))
- **Without analysis:** $(count(p -> !p["has_analysis"], three_letter_packages))

---

## All 3-Letter Packages

| Package | PR # | Status | Comments | Merged By | Key Reviewer | Comment | Data | Analysis |
|---------|------|--------|----------|-----------|--------------|---------|------|----------|
"""

    for pkg in three_letter_packages
        name = pkg["package_name"]
        pr_num = pkg["pr_number"]
        status = pkg["merged"] ? "✅ Merged" : "❌ Closed"
        num_comments = pkg["num_comments"]
        merged_by = pkg["merged_by"] !== nothing ? "@$(pkg["merged_by"])" : "—"
        data_link = "[JSON]($(pkg["pr_file"]))"

        analysis_link = if pkg["has_analysis"]
            "[Analysis]($(pkg["analysis_file"]))"
        else
            "—"
        end

        # Key reviewer from influential comment
        key_reviewer = "—"
        comment_text = "—"
        if pkg["influential_comment"] !== nothing
            comment = pkg["influential_comment"]
            author = get(comment, "author", "unknown")
            influence = get(comment, "influence", 0)
            key_reviewer = "@$author"

            # Get comment text and clean it for markdown table
            raw_text = get(comment, "text", "")
            # Replace newlines with <br> for markdown tables
            # Escape pipes to prevent breaking the table
            comment_text = replace(raw_text, "|" => "\\|")
            comment_text = replace(comment_text, r"\R" => "<br>")
            # Truncate if too long (optional)
            if length(comment_text) > 500
                comment_text = comment_text[1:500] * "..."
            end
        end

        report *= "| $name | #$pr_num | $status | $num_comments | $merged_by | $key_reviewer | $comment_text | $data_link | $analysis_link |\n"
    end

    # Save report
    output_file = "three-letter-packages-report.md"
    open(output_file, "w") do f
        write(f, report)
    end

    println("\n✅ Report saved to: $output_file")
    println("\nSummary:")
    println("  Total 3-letter packages: $(length(three_letter_packages))")
    println("  Merged: $(count(p -> p["merged"], three_letter_packages))")
    println("  Closed: $(count(p -> !p["merged"], three_letter_packages))")
    println("  With analysis: $(count(p -> p["has_analysis"], three_letter_packages))")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
