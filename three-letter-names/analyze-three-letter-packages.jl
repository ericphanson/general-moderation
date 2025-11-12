#!/usr/bin/env julia --project=.

using JSON
using Dates

"""Find all PR JSON files in data/ directory"""
function find_all_pr_files(dir="../data")
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
    # Replace ../data/ with ../analysis/ and add -analysis suffix
    analysis_file = replace(pr_file, r"\.\./data/" => "../analysis/", count=1)
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

    # Load categories.json
    println("Loading categories.json...")
    categories = JSON.parsefile("categories.json")

    # Create a lookup map for categories using package key (PackageName-prNNNNN)
    pkg_categories = Dict()
    for (key, cat_data) in categories
        pkg_categories[key] = cat_data
    end

    # Add category info to packages
    for pkg in three_letter_packages
        # Create key in format PackageName-prNNNNN
        base_name = replace(pkg["package_name"], r"\.jl$" => "")
        key = "$(base_name)-pr$(pkg["pr_number"])"

        if haskey(pkg_categories, key)
            pkg["category"] = pkg_categories[key]["category"]
            pkg["proof"] = pkg_categories[key]["proof"]
        else
            pkg["category"] = "Uncategorized"
            pkg["proof"] = "N/A"
        end
    end

    # Define category order (accepted first, then rejected)
    category_order = [
        # Accepted
        "Library Wrapper",
        "Pre-existing/Grandfathered",
        "Standard File Format",
        "Domain-Specific Acronym",
        "Company/Brand Name",
        "Discretionary Approval",
        # Rejected
        "Duplicate/Superseded PR",
        "Rejected: Acronym Not Widely Known",
        "Rejected: Poor Discoverability",
        "Rejected: Name Collision/Ambiguity",
        "Technical Rejection",
        "Rejected: Generic/Other"
    ]

    # Group packages by category
    packages_by_category = Dict{String, Vector}()
    for cat in category_order
        packages_by_category[cat] = []
    end

    for pkg in three_letter_packages
        cat = get(pkg, "category", "Uncategorized")
        if haskey(packages_by_category, cat)
            push!(packages_by_category[cat], pkg)
        end
    end

    # Sort each category's packages by name
    for cat in category_order
        sort!(packages_by_category[cat], by=x -> x["package_name"])
    end

    # Generate markdown report
    println("Generating markdown report with category sections...")

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

"""

    # Generate sections for each category
    for cat in category_order
        pkgs_in_cat = packages_by_category[cat]

        if isempty(pkgs_in_cat)
            continue
        end

        # Determine section emoji
        status_emoji = startswith(cat, "Rejected") || cat in ["Duplicate/Superseded PR", "Technical Rejection"] ? "❌" : "✅"

        report *= """
## $(status_emoji) $cat ($(length(pkgs_in_cat)))

| Package | PR # | Status | Proof/Evidence | Data | Analysis |
|---------|------|--------|----------------|------|----------|
"""

        for pkg in pkgs_in_cat
            name = pkg["package_name"]
            pr_num = pkg["pr_number"]
            status = pkg["merged"] ? "✅ Merged" : "❌ Closed"
            data_link = "[JSON]($(pkg["pr_file"]))"

            analysis_link = if pkg["has_analysis"]
                "[Analysis]($(pkg["analysis_file"]))"
            else
                "—"
            end

            # Get proof and clean it for markdown table
            proof = get(pkg, "proof", "—")
            # Escape pipes and newlines for markdown table
            proof_clean = replace(proof, "|" => "\\|")
            proof_clean = replace(proof_clean, r"\R" => " ")
            # Truncate if too long
            if length(proof_clean) > 300
                proof_clean = proof_clean[1:300] * "..."
            end

            report *= "| $name | #$pr_num | $status | $proof_clean | $data_link | $analysis_link |\n"
        end

        report *= "\n"
    end

    # Save report
    output_file = "three-letter-packages-report.md"
    open(output_file, "w") do f
        write(f, report)
    end

    println("\n✅ Report saved to: $output_file")
    println("\nSummary by Category:")
    for cat in category_order
        count = length(packages_by_category[cat])
        if count > 0
            println("  $cat: $count")
        end
    end
    println("\nTotal: $(length(three_letter_packages)) packages")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
