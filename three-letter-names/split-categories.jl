using JSON

println("Splitting categories.json into accepted.json and rejected.json...")
println("="^80)

# Read categories
categories = JSON.parsefile("categories.json")

# Define accepted categories
accepted_categories = [
    "Library Wrapper",
    "Pre-existing/Grandfathered",
    "Standard File Format",
    "Domain-Specific Acronym",
    "Company/Brand Name",
    "Discretionary Approval"
]

# Split into accepted and rejected
accepted = Dict()
rejected = Dict()

for (key, data) in categories
    category = data["category"]
    if category in accepted_categories
        accepted[key] = data
    else
        rejected[key] = data
    end
end

# Write to separate files
open("accepted.json", "w") do f
    JSON.print(f, accepted, 2)
end

open("rejected.json", "w") do f
    JSON.print(f, rejected, 2)
end

println("✓ Split complete!")
println()
println("Accepted packages: $(length(accepted))")
println("Rejected packages: $(length(rejected))")
println()
println("Files created:")
println("  - accepted.json ($(length(accepted)) packages)")
println("  - rejected.json ($(length(rejected)) packages)")
