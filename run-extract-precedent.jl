#!/usr/bin/env julia

# Get list of JSON files from ripgrep
files = readlines(`rg -No 'data/[A-Z]/\w+-pr\d+\.json' three-letter-packages-report.md`)

println("Found $(length(files)) files to process")

# Process each file
for (i, file) in enumerate(files)
    println("[$i/$(length(files))] Processing $file...")
    run(`julia --optimize=0 --compile=min --startup-file=no --project=. extract-precedents.jl $file`)
end

println("\n✓ Complete!")
