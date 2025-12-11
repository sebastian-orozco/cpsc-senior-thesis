#!/bin/bash

# Debug flag: set to true to save full output of each run to out.txt
DEBUG_OUTPUT=true

# Parse arguments: config_type [runs]
# config_type: threading, mpmc, or ping_pong
# runs: number of runs (default: 10)
CONFIG_TYPE=${1:-threading}
RUNS=${2:-10}

# Validate config type
if [ "$CONFIG_TYPE" != "threading" ] && [ "$CONFIG_TYPE" != "mpmc" ] && [ "$CONFIG_TYPE" != "ping_pong" ]; then
    echo "Error: Invalid config type '$CONFIG_TYPE'"
    echo "Usage: $0 [threading|mpmc|ping_pong] [runs]"
    echo "  threading: benchmarks betterC and native configs"
    echo "  mpmc: benchmarks betterC_mpmc and native_mpmc configs"
    echo "  ping_pong: benchmarks betterC_ping_pong and native_ping_pong configs"
    exit 1
fi

# Map config type to actual dub configurations
case "$CONFIG_TYPE" in
    threading)
        NATIVE_CONFIG="native"
        BETTERC_CONFIG="betterC"
        CONFIG_NAME="Threading"
        ;;
    mpmc)
        NATIVE_CONFIG="native_mpmc"
        BETTERC_CONFIG="betterC_mpmc"
        CONFIG_NAME="MPMC"
        ;;
    ping_pong)
        NATIVE_CONFIG="native_ping_pong"
        BETTERC_CONFIG="betterC_ping_pong"
        CONFIG_NAME="Ping-Pong"
        ;;
esac

# Output file for debug mode
DEBUG_OUTPUT_FILE="out_${CONFIG_TYPE}.txt"

# Clear output file if debug mode is enabled
if [ "$DEBUG_OUTPUT" = true ]; then
    > "$DEBUG_OUTPUT_FILE"  # Clear the file
    echo "Debug mode enabled: full output will be saved to $DEBUG_OUTPUT_FILE"
fi

echo "Starting $CONFIG_NAME benchmarks (will clean before each run)..."
echo "Config type: $CONFIG_TYPE"
echo "Number of runs: $RUNS"

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

# Function to run benchmarks for a given configuration
run_benchmark() {
    local config=$1
    local config_name=$2
    
    echo ""
    echo "========================================="
    echo "Running $config_name benchmarks ($RUNS runs)..."
    echo "========================================="
    
    # Arrays to store times
    declare -a real_times
    declare -a user_times
    declare -a sys_times
    
    # Arrays to store memory and instruction stats
    declare -a max_rss
    declare -a instructions
    declare -a peak_memory
    
    # Run the builds and collect timing data
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
        /usr/bin/time -l dub run --compiler=ldc2 --config=$config 2> "$temp_file" > /dev/null
        
        # Save full output to debug file if enabled
        if [ "$DEBUG_OUTPUT" = true ]; then
            echo "========================================" >> "$DEBUG_OUTPUT_FILE"
            echo "Run $i/$RUNS - Config: $config_name" >> "$DEBUG_OUTPUT_FILE"
            echo "========================================" >> "$DEBUG_OUTPUT_FILE"
            cat "$temp_file" >> "$DEBUG_OUTPUT_FILE"
            echo "" >> "$DEBUG_OUTPUT_FILE"
        fi
        
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
    local real_avg=$(calculate_average "${real_times[@]}")
    local user_avg=$(calculate_average "${user_times[@]}")
    local sys_avg=$(calculate_average "${sys_times[@]}")
    
    local real_stddev=$(calculate_stddev "${real_times[@]}")
    local user_stddev=$(calculate_stddev "${user_times[@]}")
    local sys_stddev=$(calculate_stddev "${sys_times[@]}")
    
    # Calculate statistics for memory and instructions
    local max_rss_avg=$(calculate_average "${max_rss[@]}")
    local instructions_avg=$(calculate_average "${instructions[@]}")
    local peak_mem_avg=$(calculate_average "${peak_memory[@]}")
    
    local max_rss_stddev=$(calculate_stddev "${max_rss[@]}")
    local instructions_stddev=$(calculate_stddev "${instructions[@]}")
    local peak_mem_stddev=$(calculate_stddev "${peak_memory[@]}")
    
    # Convert memory averages to MB for readability
    local max_rss_avg_mb=$(echo "scale=2; $max_rss_avg / 1048576" | bc -l)
    local max_rss_stddev_mb=$(echo "scale=2; $max_rss_stddev / 1048576" | bc -l)
    local peak_mem_avg_mb=$(echo "scale=2; $peak_mem_avg / 1048576" | bc -l)
    local peak_mem_stddev_mb=$(echo "scale=2; $peak_mem_stddev / 1048576" | bc -l)
    
    # Return results via global variables (bash doesn't support returning arrays)
    BENCH_REAL_AVG=$real_avg
    BENCH_USER_AVG=$user_avg
    BENCH_SYS_AVG=$sys_avg
    BENCH_REAL_STDDEV=$real_stddev
    BENCH_USER_STDDEV=$user_stddev
    BENCH_SYS_STDDEV=$sys_stddev
    BENCH_MAX_RSS_AVG=$max_rss_avg_mb
    BENCH_MAX_RSS_STDDEV=$max_rss_stddev_mb
    BENCH_INSTRUCTIONS_AVG=$instructions_avg
    BENCH_INSTRUCTIONS_STDDEV=$instructions_stddev
    BENCH_PEAK_MEM_AVG=$peak_mem_avg_mb
    BENCH_PEAK_MEM_STDDEV=$peak_mem_stddev_mb
}

# Run benchmarks for native configuration
run_benchmark "$NATIVE_CONFIG" "Native ($CONFIG_NAME)"

# Store native results
native_real_avg=$BENCH_REAL_AVG
native_user_avg=$BENCH_USER_AVG
native_sys_avg=$BENCH_SYS_AVG
native_real_stddev=$BENCH_REAL_STDDEV
native_user_stddev=$BENCH_USER_STDDEV
native_sys_stddev=$BENCH_SYS_STDDEV
native_max_rss_avg=$BENCH_MAX_RSS_AVG
native_max_rss_stddev=$BENCH_MAX_RSS_STDDEV
native_instructions_avg=$BENCH_INSTRUCTIONS_AVG
native_instructions_stddev=$BENCH_INSTRUCTIONS_STDDEV
native_peak_mem_avg=$BENCH_PEAK_MEM_AVG
native_peak_mem_stddev=$BENCH_PEAK_MEM_STDDEV

# Run benchmarks for betterC configuration
run_benchmark "$BETTERC_CONFIG" "betterC ($CONFIG_NAME)"

# Store betterC results
betterc_real_avg=$BENCH_REAL_AVG
betterc_user_avg=$BENCH_USER_AVG
betterc_sys_avg=$BENCH_SYS_AVG
betterc_real_stddev=$BENCH_REAL_STDDEV
betterc_user_stddev=$BENCH_USER_STDDEV
betterc_sys_stddev=$BENCH_SYS_STDDEV
betterc_max_rss_avg=$BENCH_MAX_RSS_AVG
betterc_max_rss_stddev=$BENCH_MAX_RSS_STDDEV
betterc_instructions_avg=$BENCH_INSTRUCTIONS_AVG
betterc_instructions_stddev=$BENCH_INSTRUCTIONS_STDDEV
betterc_peak_mem_avg=$BENCH_PEAK_MEM_AVG
betterc_peak_mem_stddev=$BENCH_PEAK_MEM_STDDEV

# Print all results
echo ""
echo "========================================="
echo "Final Benchmark Results: $CONFIG_NAME ($RUNS runs each)"
echo "========================================="
echo ""
echo "Native Config:"
printf "  Real time:        avg = %8.4f s, stddev = %8.4f s\n" "$native_real_avg" "$native_real_stddev"
printf "  User time:        avg = %8.4f s, stddev = %8.4f s\n" "$native_user_avg" "$native_user_stddev"
printf "  Sys time:         avg = %8.4f s, stddev = %8.4f s\n" "$native_sys_avg" "$native_sys_stddev"
printf "  Max RSS:          avg = %8.2f MB, stddev = %8.2f MB\n" "$native_max_rss_avg" "$native_max_rss_stddev"
printf "  Instructions:     avg = %12.0f, stddev = %12.0f\n" "$native_instructions_avg" "$native_instructions_stddev"
printf "  Peak Memory:      avg = %8.2f MB, stddev = %8.2f MB\n" "$native_peak_mem_avg" "$native_peak_mem_stddev"
echo ""
echo "betterC Config:"
printf "  Real time:        avg = %8.4f s, stddev = %8.4f s\n" "$betterc_real_avg" "$betterc_real_stddev"
printf "  User time:        avg = %8.4f s, stddev = %8.4f s\n" "$betterc_user_avg" "$betterc_user_stddev"
printf "  Sys time:         avg = %8.4f s, stddev = %8.4f s\n" "$betterc_sys_avg" "$betterc_sys_stddev"
printf "  Max RSS:          avg = %8.2f MB, stddev = %8.2f MB\n" "$betterc_max_rss_avg" "$betterc_max_rss_stddev"
printf "  Instructions:     avg = %12.0f, stddev = %12.0f\n" "$betterc_instructions_avg" "$betterc_instructions_stddev"
printf "  Peak Memory:      avg = %8.2f MB, stddev = %8.2f MB\n" "$betterc_peak_mem_avg" "$betterc_peak_mem_stddev"
echo "========================================="

# Remind user about debug output file if enabled
if [ "$DEBUG_OUTPUT" = true ]; then
    echo ""
    echo "Debug output saved to: $DEBUG_OUTPUT_FILE"
fi
