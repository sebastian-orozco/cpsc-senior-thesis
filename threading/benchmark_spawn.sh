#!/bin/bash

# Number of runs (default: 10)
RUNS=${1:-10}

echo "Starting spawn benchmarks (will clean before each run)..."

# Function to convert time string to seconds
# Handles both formats:
# - zsh format: "1.234s" or "1m2.345s"
# - bash format: "0m1.234s"
time_to_seconds() {
    local time_str=$1
    if [ -z "$time_str" ]; then
        echo "0"
        return
    fi
    
    # Check if it contains 'm' (minutes)
    if echo "$time_str" | grep -q 'm'; then
        # Has minutes: "0m1.234s" or "1m2.345s"
        local minutes=$(echo "$time_str" | sed 's/m.*//')
        local seconds=$(echo "$time_str" | sed 's/.*m//' | sed 's/s//')
        if [ -z "$minutes" ]; then
            minutes=0
        fi
        echo "$minutes * 60 + $seconds" | bc -l
    else
        # Just seconds: "1.234s"
        local seconds=$(echo "$time_str" | sed 's/s//')
        echo "$seconds" | bc -l
    fi
}

# Function to calculate average
calculate_average() {
    local arr=("$@")
    local sum=0
    local count=${#arr[@]}
    for val in "${arr[@]}"; do
        sum=$(echo "$sum + $val" | bc -l)
    done
    echo "scale=4; $sum / $count" | bc -l
}

# Function to calculate standard deviation
calculate_stddev() {
    local arr=("$@")
    local avg=$(calculate_average "${arr[@]}")
    local sum_sq_diff=0
    local count=${#arr[@]}
    for val in "${arr[@]}"; do
        local diff=$(echo "$val - $avg" | bc -l)
        local sq_diff=$(echo "$diff * $diff" | bc -l)
        sum_sq_diff=$(echo "$sum_sq_diff + $sq_diff" | bc -l)
    done
    local variance=$(echo "scale=4; $sum_sq_diff / $count" | bc -l)
    echo "scale=4; sqrt($variance)" | bc -l
}

# Arrays to store times
declare -a real_times
declare -a user_times
declare -a sys_times

# Arrays to store memory and instruction stats
declare -a max_rss
declare -a instructions
declare -a peak_memory

# Run the benchmarks and collect timing data
for i in $(seq 1 $RUNS); do
    echo "Run $i/$RUNS..."
    
    # Clean before each run for consistent benchmarks
    dub clean > /dev/null 2>&1
    
    # Use a temp file to capture time output
    temp_file=$(mktemp)
    
    # Run with /usr/bin/time -l to get detailed stats (macOS format)
    # This provides: time, max RSS, instructions retired, peak memory footprint
    # Time output goes to stderr, so capture stderr to temp file
    # Redirect stdout to /dev/null to suppress dub output
    /usr/bin/time -l dub run --compiler=ldc2 --config=native_spawn 2> "$temp_file" > /dev/null
    
    # Parse time output - look for line with "real" keyword
    # Format: "        3.06 real         1.93 user         0.45 sys"
    # Time output is usually at the end, so get the last matching line
    time_line=$(grep " real " "$temp_file" | tail -1)
    if [ -n "$time_line" ]; then
        # Extract the three time values using awk (handles whitespace better)
        real_str=$(echo "$time_line" | awk '{print $1}')
        user_str=$(echo "$time_line" | awk '{print $3}')
        sys_str=$(echo "$time_line" | awk '{print $5}')
        # Add 's' suffix if not present for time_to_seconds function
        if [[ ! "$real_str" =~ s$ ]] && [[ "$real_str" =~ ^[0-9] ]]; then
            real_str="${real_str}s"
        fi
        if [[ ! "$user_str" =~ s$ ]] && [[ "$user_str" =~ ^[0-9] ]]; then
            user_str="${user_str}s"
        fi
        if [[ ! "$sys_str" =~ s$ ]] && [[ "$sys_str" =~ ^[0-9] ]]; then
            sys_str="${sys_str}s"
        fi
    else
        real_str="0s"
        user_str="0s"
        sys_str="0s"
    fi
    
    # Parse maximum resident set size (bytes on macOS)
    # Format: "            60780544  maximum resident set size"
    max_rss_line=$(grep "maximum resident set size" "$temp_file" | tail -1)
    if [ -n "$max_rss_line" ]; then
        max_rss_bytes=$(echo "$max_rss_line" | awk '{print $1}')
        # Remove any leading whitespace
        max_rss_bytes=$(echo "$max_rss_bytes" | sed 's/^[[:space:]]*//')
    fi
    if [ -z "$max_rss_bytes" ] || [ "$max_rss_bytes" = "" ]; then
        max_rss_bytes=0
    fi
    
    # Parse instructions retired
    # Format: "           895403572  instructions retired"
    instructions_line=$(grep "instructions retired" "$temp_file" | tail -1)
    if [ -n "$instructions_line" ]; then
        instructions_retired=$(echo "$instructions_line" | awk '{print $1}')
        # Remove any leading whitespace
        instructions_retired=$(echo "$instructions_retired" | sed 's/^[[:space:]]*//')
    fi
    if [ -z "$instructions_retired" ] || [ "$instructions_retired" = "" ]; then
        instructions_retired=0
    fi
    
    # Parse peak memory footprint (bytes on macOS)
    # Format: "             3429376  peak memory footprint"
    peak_mem_line=$(grep "peak memory footprint" "$temp_file" | tail -1)
    if [ -n "$peak_mem_line" ]; then
        peak_mem_bytes=$(echo "$peak_mem_line" | awk '{print $1}')
        # Remove any leading whitespace
        peak_mem_bytes=$(echo "$peak_mem_bytes" | sed 's/^[[:space:]]*//')
    fi
    if [ -z "$peak_mem_bytes" ] || [ "$peak_mem_bytes" = "" ]; then
        peak_mem_bytes=0
    fi
    
    # Clean up temp file
    rm "$temp_file"
    
    # Convert to seconds
    real_sec=$(time_to_seconds "$real_str")
    user_sec=$(time_to_seconds "$user_str")
    sys_sec=$(time_to_seconds "$sys_str")
    
    # Convert memory from bytes to MB for readability
    if [ "$max_rss_bytes" != "0" ] && [ -n "$max_rss_bytes" ]; then
        max_rss_mb=$(echo "scale=2; $max_rss_bytes / 1048576" | bc -l)
    else
        max_rss_mb="0.00"
    fi
    
    if [ "$peak_mem_bytes" != "0" ] && [ -n "$peak_mem_bytes" ]; then
        peak_mem_mb=$(echo "scale=2; $peak_mem_bytes / 1048576" | bc -l)
    else
        peak_mem_mb="0.00"
    fi
    
    # Store in arrays
    real_times+=($real_sec)
    user_times+=($user_sec)
    sys_times+=($sys_sec)
    max_rss+=($max_rss_bytes)
    instructions+=($instructions_retired)
    peak_memory+=($peak_mem_bytes)
    
    echo "  real: $real_str ($real_sec s), user: $user_str ($user_sec s), sys: $sys_str ($sys_sec s)"
    echo "  max RSS: ${max_rss_mb} MB, instructions: $instructions_retired, peak mem: ${peak_mem_mb} MB"
done

# Calculate statistics for time
real_avg=$(calculate_average "${real_times[@]}")
user_avg=$(calculate_average "${user_times[@]}")
sys_avg=$(calculate_average "${sys_times[@]}")

real_stddev=$(calculate_stddev "${real_times[@]}")
user_stddev=$(calculate_stddev "${user_times[@]}")
sys_stddev=$(calculate_stddev "${sys_times[@]}")

# Calculate statistics for memory and instructions
max_rss_avg=$(calculate_average "${max_rss[@]}")
instructions_avg=$(calculate_average "${instructions[@]}")
peak_mem_avg=$(calculate_average "${peak_memory[@]}")

max_rss_stddev=$(calculate_stddev "${max_rss[@]}")
instructions_stddev=$(calculate_stddev "${instructions[@]}")
peak_mem_stddev=$(calculate_stddev "${peak_memory[@]}")

# Convert memory averages to MB for readability
max_rss_avg_mb=$(echo "scale=2; $max_rss_avg / 1048576" | bc -l)
max_rss_stddev_mb=$(echo "scale=2; $max_rss_stddev / 1048576" | bc -l)
peak_mem_avg_mb=$(echo "scale=2; $peak_mem_avg / 1048576" | bc -l)
peak_mem_stddev_mb=$(echo "scale=2; $peak_mem_stddev / 1048576" | bc -l)

# Print results
echo ""
echo "========================================="
echo "Spawn Benchmark Results ($RUNS runs)"
echo "========================================="
printf "Real time:        avg = %8.4f s, stddev = %8.4f s\n" "$real_avg" "$real_stddev"
printf "User time:        avg = %8.4f s, stddev = %8.4f s\n" "$user_avg" "$user_stddev"
printf "Sys time:         avg = %8.4f s, stddev = %8.4f s\n" "$sys_avg" "$sys_stddev"
printf "Max RSS:          avg = %8.2f MB, stddev = %8.2f MB\n" "$max_rss_avg_mb" "$max_rss_stddev_mb"
printf "Instructions:     avg = %12.0f, stddev = %12.0f\n" "$instructions_avg" "$instructions_stddev"
printf "Peak Memory:      avg = %8.2f MB, stddev = %8.2f MB\n" "$peak_mem_avg_mb" "$peak_mem_stddev_mb"
echo "========================================="

