#!/bin/bash

# File Scanner Generator
# Generates standalone PowerShell and Bash scripts with config embedded

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/filescanner.config"
OUTPUT_PS1="${SCRIPT_DIR}/filescanner_standalone.ps1"
OUTPUT_SH="${SCRIPT_DIR}/filescanner_standalone.sh"

echo "=== File Scanner Generator ==="
echo "Reading config from: $CONFIG_FILE"
echo ""

# Check if config exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: Config file not found: $CONFIG_FILE"
    exit 1
fi

# Function to escape strings for PowerShell
escape_ps() {
    echo "$1" | sed "s/'/\\\'/g"
}

# Function to escape strings for Bash
escape_bash() {
    echo "$1" | sed 's/"/\\"/g' | sed "s/'/\\'/g"
}

echo "Generating standalone PowerShell script..."

# Generate PowerShell script
cat > "$OUTPUT_PS1" << 'PSEOF'
# File Scanner - Standalone PowerShell Version
# Generated from config - no external config file needed

param(
    [Parameter(Mandatory=$true, HelpMessage="Root directory to search")]
    [string]$SearchRoot,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFile = "findings_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt",
    
    [Parameter(Mandatory=$false)]
    [switch]$Verbose,
    
    [Parameter(Mandatory=$false)]
    [switch]$Help
)

if ($Help) {
    Write-Host @"
File Scanner - Standalone PowerShell Edition
Embedded configuration - no config file required

USAGE:
    .\filescanner_standalone.ps1 -SearchRoot <path> [options]

PARAMETERS:
    -SearchRoot <path>  Root directory to search (REQUIRED)
    -OutputFile <path>  Output file path (default: findings_YYYYMMDD_HHMMSS.txt)
    -Verbose           Show detailed output
    -Help              Show this help message

EXAMPLES:
    .\filescanner_standalone.ps1 -SearchRoot C:\inetpub\wwwroot
    .\filescanner_standalone.ps1 -SearchRoot C:\Users\John\Documents -Verbose
    .\filescanner_standalone.ps1 -SearchRoot C:\Projects -OutputFile results.txt

REMOTE EXECUTION:
    IEX (irm https://your-server/filescanner_standalone.ps1)
    .\filescanner_standalone.ps1 -SearchRoot C:\data -Verbose

"@
    exit 0
}

# Validate search root
if (-not (Test-Path $SearchRoot)) {
    Write-Error "Search root does not exist: $SearchRoot"
    exit 1
}

# Create output directory
$outputDir = Split-Path -Parent $OutputFile
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Embedded configuration
$Config = @'
PSEOF

# Read and embed the config file
while IFS= read -r line || [[ -n "$line" ]]; do
    # Escape single quotes for PowerShell
    escaped_line=$(echo "$line" | sed "s/'/\`'/g")
    echo "$escaped_line" >> "$OUTPUT_PS1"
done < "$CONFIG_FILE"

# Continue PowerShell script
cat >> "$OUTPUT_PS1" << 'PSEOF'
'@

# Scanner class
class FileScanner {
    [string]$SearchRoot
    [string]$OutputFile
    [bool]$IsVerbose
    [hashtable]$SectionExamples
    [string[]]$ConfigLines

    FileScanner([string]$root, [string]$output, [bool]$verbose, [string]$configText) {
        $this.SearchRoot = $root
        $this.OutputFile = $output
        $this.IsVerbose = $verbose
        $this.SectionExamples = @{}
        $this.ConfigLines = $configText -split "`n"
    }

    [void]Log([string]$message, [bool]$toConsole = $false) {
        if ($toConsole -or $this.IsVerbose) {
            Write-Host $message
        }
        Add-Content -Path $this.OutputFile -Value $message
    }

    [string[]]SearchFiles([string]$pattern, [string[]]$extensions) {
        $results = @()
        $regex = [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        
        try {
            Get-ChildItem -Path $this.SearchRoot -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                $file = $_
                
                if ($extensions -and $extensions.Count -gt 0) {
                    $matchesExt = $false
                    foreach ($ext in $extensions) {
                        if ($file.Name -like $ext) {
                            $matchesExt = $true
                            break
                        }
                    }
                    if (-not $matchesExt) { return }
                }
                
                try {
                    $lineNum = 0
                    Get-Content -Path $file.FullName -ErrorAction SilentlyContinue | ForEach-Object {
                        $lineNum++
                        if ($regex.IsMatch($_)) {
                            $results += "$($file.FullName):$($lineNum):$_"
                        }
                    }
                } catch {}
            }
        } catch {}
        
        return $results
    }

    [string[]]FindFiles([string[]]$patterns, [string[]]$namePatterns) {
        $results = @()
        
        try {
            Get-ChildItem -Path $this.SearchRoot -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                $file = $_
                
                if ($patterns) {
                    foreach ($pattern in $patterns) {
                        if ($file.Name -like $pattern) {
                            $results += $file.FullName
                            return
                        }
                    }
                }
                
                if ($namePatterns) {
                    foreach ($pattern in $namePatterns) {
                        if ($file.Name -like $pattern) {
                            $results += $file.FullName
                            return
                        }
                    }
                }
            }
        } catch {}
        
        return $results
    }

    [string[]]FindAndCatFiles([string[]]$namePatterns) {
        $results = @()
        $files = $this.FindFiles($null, $namePatterns)
        
        foreach ($file in $files) {
            try {
                $content = Get-Content -Path $file -Raw -ErrorAction SilentlyContinue
                if ($content) {
                    $results += "=== $file ==="
                    $results += $content
                }
            } catch {}
        }
        
        return $results
    }

    [string[]]ParseList([string]$value) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            return @()
        }
        return $value.Split(',') | ForEach-Object { $_.Trim() }
    }

    [string]BuildActualCommand([string]$command, [string[]]$keywords, [string[]]$extensions, [string[]]$files) {
        $actualCommand = $command
        
        if ($keywords -and $keywords.Count -gt 0 -and $actualCommand -match 'KEYWORDS') {
            $keywordPattern = $keywords -join '|'
            $actualCommand = $actualCommand -replace 'KEYWORDS', $keywordPattern
        }
        
        if ($extensions -and $extensions.Count -gt 0 -and $actualCommand -match 'EXTENSIONS') {
            if ($actualCommand -match 'Get-ChildItem|Select-String') {
                $includeList = $extensions -join ','
                $actualCommand = $actualCommand -replace 'EXTENSIONS', "-Include $includeList"
            }
        }
        
        if ($files -and $files.Count -gt 0 -and $actualCommand -match 'FILES') {
            if ($actualCommand -match 'Get-ChildItem') {
                $includeList = $files -join ','
                $actualCommand = $actualCommand -replace 'FILES', "-Include $includeList"
            }
        }
        
        return $actualCommand
    }

    [void]ExecuteSection([string]$sectionName, [string]$windowsCommand, [string[]]$keywords, [string[]]$extensions, [string[]]$files) {
        $this.Log("`n=== $sectionName ===", $false)
        
        $actualCommand = $this.BuildActualCommand($windowsCommand, $keywords, $extensions, $files)
        
        if ($this.IsVerbose) {
            $this.Log("Command: $actualCommand", $true)
        }
        
        $results = @()
        
        if ($windowsCommand -match 'Select-String') {
            if ($keywords) {
                $pattern = $keywords -join '|'
                $results = $this.SearchFiles($pattern, $extensions)
            }
        } elseif ($windowsCommand -match 'Get-ChildItem.*Get-Content') {
            $patterns = if ($files) { $files } else { $extensions }
            $results = $this.FindAndCatFiles($patterns)
        } elseif ($windowsCommand -match 'Get-ChildItem') {
            if ($extensions) {
                $results = $this.FindFiles($extensions, $null)
            } elseif ($files) {
                $results = $this.FindFiles($null, $files)
            }
        }
        
        if ($results -and $results.Count -gt 0) {
            foreach ($result in $results) {
                $this.Log($result, $this.IsVerbose)
            }
        } elseif ($this.IsVerbose) {
            $this.Log("No matches found", $true)
        }
    }

    [hashtable[]]ParseConfig() {
        $sections = @()
        $currentSection = $null
        
        foreach ($line in $this.ConfigLines) {
            $line = $line.Trim()
            
            if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
                continue
            }
            
            if ($line -match '^\[(.+)\]$') {
                if ($currentSection) {
                    $sections += $currentSection
                }
                $currentSection = @{
                    Name = $matches[1]
                    WindowsCommand = ''
                    Keywords = @()
                    Extensions = @()
                    Files = @()
                }
                continue
            }
            
            if ($line -match '^Windows Command:\s*(.+)$') {
                $currentSection.WindowsCommand = $matches[1].Trim()
            } elseif ($line -match '^(Linux Command|Windows Example|Linux Example):') {
                # Skip
            } elseif ($line -match '^Keywords:\s*(.+)$') {
                $currentSection.Keywords = $this.ParseList($matches[1])
            } elseif ($line -match '^Extensions:\s*(.+)$') {
                $currentSection.Extensions = $this.ParseList($matches[1])
            } elseif ($line -match '^Files:\s*(.+)$') {
                $currentSection.Files = $this.ParseList($matches[1])
            }
        }
        
        if ($currentSection) {
            $sections += $currentSection
        }
        
        return $sections
    }

    [void]Run() {
        $header = @(
            "Starting search from: $($this.SearchRoot)"
            "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            "=" * 40
        )
        $header | Set-Content -Path $this.OutputFile
        
        if ($this.IsVerbose) {
            $header | ForEach-Object { Write-Host $_ }
        }
        
        $sections = $this.ParseConfig()
        foreach ($section in $sections) {
            if ($section.WindowsCommand) {
                $this.ExecuteSection(
                    $section.Name,
                    $section.WindowsCommand,
                    $section.Keywords,
                    $section.Extensions,
                    $section.Files
                )
            }
        }
        
        $footer = @(
            ""
            "=" * 40
            "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        )
        $footer | Add-Content -Path $this.OutputFile
        
        if ($this.IsVerbose) {
            $footer | ForEach-Object { Write-Host $_ }
        }
        
        Write-Host "Results saved to: $($this.OutputFile)" -ForegroundColor Green
    }
}

# Main execution
$scanner = [FileScanner]::new($SearchRoot, $OutputFile, $Verbose.IsPresent, $Config)

try {
    $scanner.Run()
} catch {
    Write-Error "Error during scan: $_"
    exit 1
}
PSEOF

echo "✓ Generated: $OUTPUT_PS1"
echo ""

# Generate Bash script
echo "Generating standalone Bash script..."

cat > "$OUTPUT_SH" << 'BASHEOF'
#!/bin/bash

# File Scanner - Standalone Bash Version
# Generated from config - no external config file needed

# Default values
SEARCH_ROOT=""
OUTPUT_FILE="findings_$(date +%Y%m%d_%H%M%S).txt"
VERBOSE=false

show_help() {
    cat << EOF
File Scanner - Standalone Bash Edition
Embedded configuration - no config file required

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

# Embedded configuration
read -r -d '' CONFIG << 'CONFIGEOF'
BASHEOF

# Embed the config
cat "$CONFIG_FILE" >> "$OUTPUT_SH"

cat >> "$OUTPUT_SH" << 'BASHEOF'
CONFIGEOF

# Helper functions
build_actual_command() {
    local cmd="$1"
    local kw="$2"
    local ext="$3"
    local fls="$4"
    
    local actual_command="$cmd"
    
    if [[ -n "$kw" ]] && [[ "$actual_command" == *"KEYWORDS"* ]]; then
        local keyword_pattern=$(echo "$kw" | sed 's/,\s*/|/g' | sed 's/[{}\[\]]/\\&/g')
        actual_command="${actual_command//KEYWORDS/$keyword_pattern}"
    fi
    
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

# Write header
{
    echo "Starting search from: $SEARCH_ROOT"
    echo "Started: $(date)"
    echo "========================================"
} > "$OUTPUT_FILE"

[[ "$VERBOSE" == true ]] && cat "$OUTPUT_FILE"

# Parse and execute config
current_section=""
linux_command=""
keywords=""
extensions=""
files=""

process_section() {
    [[ -z "$linux_command" ]] && return
    
    local actual_command=$(build_actual_command "$linux_command" "$keywords" "$extensions" "$files")
    
    if [[ "$VERBOSE" == true ]]; then
        echo -e "\n> Running: $actual_command" | tee -a "$OUTPUT_FILE"
        eval "$actual_command" 2>/dev/null | tee -a "$OUTPUT_FILE"
    else
        result=$(eval "$actual_command" 2>/dev/null)
        [[ -n "$result" ]] && echo "$result" >> "$OUTPUT_FILE"
    fi
    
    linux_command=""
    keywords=""
    extensions=""
    files=""
}

while IFS= read -r line; do
    if [[ "$line" =~ ^\[.*\]$ ]]; then
        process_section
        current_section="${line:1:-1}"
        
        if [[ "$VERBOSE" == true ]]; then
            echo -e "\n=== $current_section ===" | tee -a "$OUTPUT_FILE"
        else
            echo -e "\n=== $current_section ===" >> "$OUTPUT_FILE"
        fi
        continue
    fi
    
    [[ "$line" =~ ^#.*$ ]] || [[ -z "$line" ]] && continue
    
    if [[ "$line" =~ ^"Linux Command: "(.+)$ ]]; then
        linux_command="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^"Keywords: "(.+)$ ]]; then
        keywords="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^"Extensions: "(.+)$ ]]; then
        extensions="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^"Files: "(.+)$ ]]; then
        files="${BASH_REMATCH[1]}"
    fi
done <<< "$CONFIG"

process_section

# Footer
{
    echo ""
    echo "========================================"
    echo "Completed: $(date)"
} >> "$OUTPUT_FILE"

[[ "$VERBOSE" == true ]] && tail -3 "$OUTPUT_FILE"

echo "Results saved to: $OUTPUT_FILE"
BASHEOF

chmod +x "$OUTPUT_SH"

echo "✓ Generated: $OUTPUT_SH"
echo ""
echo "=== Generation Complete ==="
echo ""
echo "Standalone scripts created:"
echo "  PowerShell: $OUTPUT_PS1"
echo "  Bash:       $OUTPUT_SH"
echo ""
echo "Usage:"
echo "  PowerShell: .\\filescanner_standalone.ps1 -SearchRoot C:\\path"
echo "  Bash:       ./filescanner_standalone.sh -r /path"
echo ""
echo "Remote execution (PowerShell):"
echo "  IEX (irm https://your-server/filescanner_standalone.ps1)"
echo ""