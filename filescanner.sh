#!/bin/bash

# Default values
CONFIG_FILE="./filescanner.config"
SEARCH_ROOT=""
OUTPUT_FILE="findings_$(date +%Y%m%d_%H%M%S).txt"
VERBOSE=false

# Help function
show_help() {
    cat << EOF
Usage: ./search.sh [OPTIONS]

Recursively search filesystem for sensitive files and keywords based on config file.

OPTIONS:
    -c, --config FILE       Path to config file (default: ./filescanner.config)
    -r, --root DIR          Root directory to search from (REQUIRED)
    -o, --output FILE       Path to output file (default: findings_YYYYMMDD_HHMMSS.txt)
    -v, --verbose           Show commands being run and metadata (default: off)
    -h, --help              Show this help message and exit

EXAMPLES:
    # Search /var/www with default config (quiet mode)
    ./search.sh -r /var/www

    # Verbose mode - shows commands and metadata
    ./search.sh -r /var/www -v

    # Specify all parameters
    ./search.sh -c my_config.txt -r /home/user -o results/scan.txt

    # Show this help
    ./search.sh --help

CONFIG FILE FORMAT:
    [Section Name]
    Command: command_with_KEYWORDS_EXTENSIONS_FILES_placeholders
    Example: actual_command_example (auto-updated each run)
    Keywords: keyword1, keyword2, keyword3
    Extensions: *.ext1, *.ext2
    Files: file1, file2
    
    Placeholders:
    - KEYWORDS: Replaced with pipe-separated keywords
    - EXTENSIONS: Replaced with --include flags (grep) or -name flags (find)
    - FILES: Replaced with -name flags (find)

OUTPUT:
    Without -v: Only matching results are saved
    With -v: Commands, metadata, and results are saved

NOTE:
    The Example line in the config file is auto-updated each time the script runs
    to reflect the actual command that will be executed.

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -r|--root)
            SEARCH_ROOT="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run './search.sh --help' for usage information"
            exit 1
            ;;
    esac
done

# Check if search root is specified
if [[ -z "$SEARCH_ROOT" ]]; then
    echo "Error: Search root directory must be specified with -r or --root"
    echo "Run './search.sh --help' for usage information"
    exit 1
fi

# Check if search root exists
if [[ ! -d "$SEARCH_ROOT" ]]; then
    echo "Error: Search root directory does not exist: $SEARCH_ROOT"
    exit 1
fi

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Config file not found: $CONFIG_FILE"
    echo "Run './search.sh --help' for usage information"
    exit 1
fi

# Create output directory if it doesn't exist
OUTPUT_DIR=$(dirname "$OUTPUT_FILE")
if [[ ! -d "$OUTPUT_DIR" ]]; then
    mkdir -p "$OUTPUT_DIR"
fi

# Header info
if [[ "$VERBOSE" == true ]]; then
    echo "Starting search from: $SEARCH_ROOT" | tee "$OUTPUT_FILE"
    echo "Config: $CONFIG_FILE" | tee -a "$OUTPUT_FILE"
    echo "Started: $(date)" | tee -a "$OUTPUT_FILE"
    echo "========================================" | tee -a "$OUTPUT_FILE"
else
    echo "Starting search from: $SEARCH_ROOT" > "$OUTPUT_FILE"
    echo "Config: $CONFIG_FILE" >> "$OUTPUT_FILE"
    echo "Started: $(date)" >> "$OUTPUT_FILE"
    echo "========================================" >> "$OUTPUT_FILE"
fi

# Variables to track config updates
declare -A section_examples

build_actual_command() {
    local cmd="$1"
    local kw="$2"
    local ext="$3"
    local fls="$4"
    
    local actual_command="$cmd"
    
    # Replace KEYWORDS placeholder
    if [[ -n "$kw" ]] && [[ "$actual_command" == *"KEYWORDS"* ]]; then
        local keyword_pattern=$(echo "$kw" | sed 's/,\s*/|/g' | sed 's/[{}\[\]]/\\&/g')
        actual_command="${actual_command//KEYWORDS/$keyword_pattern}"
    fi
    
    # Replace EXTENSIONS placeholder
    if [[ -n "$ext" ]] && [[ "$actual_command" == *"EXTENSIONS"* ]]; then
        if [[ "$actual_command" == *"grep"* ]]; then
            local include_flags=""
            IFS=',' read -ra EXTS <<< "$ext"
            for e in "${EXTS[@]}"; do
                e=$(echo "$e" | xargs)
                include_flags="$include_flags --include=\"$e\""
            done
            actual_command="${actual_command//EXTENSIONS/$include_flags}"
        elif [[ "$actual_command" == *"find"* ]]; then
            local name_flags="\\("
            IFS=',' read -ra EXTS <<< "$ext"
            local first=true
            for e in "${EXTS[@]}"; do
                e=$(echo "$e" | xargs)
                if [[ "$first" == true ]]; then
                    name_flags="$name_flags -name \"$e\""
                    first=false
                else
                    name_flags="$name_flags -o -name \"$e\""
                fi
            done
            name_flags="$name_flags \\)"
            actual_command="${actual_command//EXTENSIONS/$name_flags}"
        fi
    fi
    
    # Replace FILES placeholder
    if [[ -n "$fls" ]] && [[ "$actual_command" == *"FILES"* ]]; then
        local name_flags="\\("
        IFS=',' read -ra FILES_ARR <<< "$fls"
        local first=true
        for f in "${FILES_ARR[@]}"; do
            f=$(echo "$f" | xargs)
            if [[ "$first" == true ]]; then
                name_flags="$name_flags -name \"$f\""
                first=false
            else
                name_flags="$name_flags -o -name \"$f\""
            fi
        done
        name_flags="$name_flags \\)"
        actual_command="${actual_command//FILES/$name_flags}"
    fi
    
    echo "$actual_command"
}

# Process config file
current_section=""
command=""
keywords=""
extensions=""
files=""

process_section() {
    if [[ -z "$command" ]]; then
        return
    fi
    
    local actual_command=$(build_actual_command "$command" "$keywords" "$extensions" "$files")
    
    # Store the example for this section (remove extra backslashes)
    local clean_command=$(echo "$actual_command" | sed 's/\\\\/\\/g')
    section_examples["$current_section"]="$clean_command"
    
    # Execute the command
    if [[ "$VERBOSE" == true ]]; then
        echo -e "\n> Running: $actual_command" | tee -a "$OUTPUT_FILE"
        eval "$actual_command" 2>/dev/null | tee -a "$OUTPUT_FILE"
    else
        result=$(eval "$actual_command" 2>/dev/null)
        if [[ -n "$result" ]]; then
            echo "$result" >> "$OUTPUT_FILE"
        fi
    fi
    
    # Reset for next section
    command=""
    keywords=""
    extensions=""
    files=""
}

# Read and process config
while IFS= read -r line || [[ -n "$line" ]]; do
    # Section header
    if [[ "$line" =~ ^\[.*\]$ ]]; then
        # Process previous section
        process_section
        
        current_section="${line:1:-1}"
        
        if [[ "$VERBOSE" == true ]]; then
            echo -e "\n=== $current_section ===" | tee -a "$OUTPUT_FILE"
        else
            echo -e "\n=== $current_section ===" >> "$OUTPUT_FILE"
        fi
        continue
    fi
    
    # Skip comments and empty lines
    [[ "$line" =~ ^#.*$ ]] || [[ -z "$line" ]] && continue
    
    # Parse metadata lines
    if [[ "$line" =~ ^"Command: "(.+)$ ]]; then
        command="${BASH_REMATCH[1]}"
        if [[ "$VERBOSE" == true ]]; then
            echo "Command template: $command" | tee -a "$OUTPUT_FILE"
        fi
    elif [[ "$line" =~ ^"Example: "(.+)$ ]]; then
        if [[ "$VERBOSE" == true ]]; then
            echo "Example (will be updated): ${BASH_REMATCH[1]}" | tee -a "$OUTPUT_FILE"
        fi
    elif [[ "$line" =~ ^"Keywords: "(.+)$ ]]; then
        keywords="${BASH_REMATCH[1]}"
        if [[ "$VERBOSE" == true ]]; then
            echo "Keywords: $keywords" | tee -a "$OUTPUT_FILE"
        fi
    elif [[ "$line" =~ ^"Extensions: "(.+)$ ]]; then
        extensions="${BASH_REMATCH[1]}"
        if [[ "$VERBOSE" == true ]]; then
            echo "Extensions: $extensions" | tee -a "$OUTPUT_FILE"
        fi
    elif [[ "$line" =~ ^"Files: "(.+)$ ]]; then
        files="${BASH_REMATCH[1]}"
        if [[ "$VERBOSE" == true ]]; then
            echo "Files: $files" | tee -a "$OUTPUT_FILE"
        fi
    fi
    
done < "$CONFIG_FILE"

# Process final section
process_section

# Update config file with new examples
TEMP_CONFIG=$(mktemp)
current_section=""

while IFS= read -r line || [[ -n "$line" ]]; do
    # Track current section
    if [[ "$line" =~ ^\[.*\]$ ]]; then
        current_section="${line:1:-1}"
        echo "$line" >> "$TEMP_CONFIG"
    elif [[ "$line" =~ ^"Example: " ]]; then
        # Replace example line with updated command
        if [[ -n "${section_examples[$current_section]}" ]]; then
            echo "Example: ${section_examples[$current_section]}" >> "$TEMP_CONFIG"
        else
            echo "$line" >> "$TEMP_CONFIG"
        fi
    else
        echo "$line" >> "$TEMP_CONFIG"
    fi
done < "$CONFIG_FILE"

# Replace original config with updated version
mv "$TEMP_CONFIG" "$CONFIG_FILE"

# Footer
if [[ "$VERBOSE" == true ]]; then
    echo -e "\n========================================" | tee -a "$OUTPUT_FILE"
    echo "Completed: $(date)" | tee -a "$OUTPUT_FILE"
    echo "Config file updated with actual commands" | tee -a "$OUTPUT_FILE"
    echo "Results saved to: $OUTPUT_FILE"
else
    echo -e "\n========================================" >> "$OUTPUT_FILE"
    echo "Completed: $(date)" >> "$OUTPUT_FILE"
    echo "Results saved to: $OUTPUT_FILE"
fi
