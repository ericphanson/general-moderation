using JSON

println("Creating batches of 15 from accepted.json...")
println("="^80)

# Read accepted packages
accepted = JSON.parsefile("accepted.json")
all_keys = collect(keys(accepted))

println("Total accepted packages: $(length(all_keys))")
println()

# Create batches of 15
batch_size = 15
num_batches = ceil(Int, length(all_keys) / batch_size)

println("Creating $num_batches batches...")
println()

for i in 1:num_batches
    start_idx = (i - 1) * batch_size + 1
    end_idx = min(i * batch_size, length(all_keys))

    batch_keys = all_keys[start_idx:end_idx]
    batch = Dict(key => accepted[key] for key in batch_keys)

    filename = "accepted-batch-$i.json"
    open(filename, "w") do f
        JSON.print(f, batch, 2)
    end

    println("✓ Batch $i: $(length(batch_keys)) packages → $filename")
end

println()
println("="^80)
println("Ready to process batches with subagents!")
println()
println("Next step: Launch subagent for batch 1")
