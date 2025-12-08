# File Scanner - PowerShell Version
# Can be executed remotely via: IEX (New-Object Net.WebClient).DownloadString('url')

param(
    [Parameter(Mandatory=$true, HelpMessage="Root directory to search")]
    [string]$SearchRoot,
    
    [Parameter(Mandatory=$false)]
    [string]$ConfigFile = ".\filescanner.config",
    
    [Parameter(Mandatory=$false)]
    [string]$OutputFile = "findings_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt",
    
    [Parameter(Mandatory=$false)]
    [switch]$Verbose,
    
    [Parameter(Mandatory=$false)]
    [switch]$Help
)

# Help function
function Show-Help {
    Write-Host @"
File Scanner - PowerShell Edition

USAGE:
    .\filescanner.ps1 -SearchRoot <path> [options]

PARAMETERS:
    -SearchRoot <path>      Root directory to search (REQUIRED)
    -ConfigFile <path>      Path to config file (default: .\filescanner.config)
    -OutputFile <path>      Output file path (default: findings_YYYYMMDD_HHMMSS.txt)
    -Verbose               Show detailed output
    -Help                  Show this help message

EXAMPLES:
    # Basic scan
    .\filescanner.ps1 -SearchRoot C:\inetpub\wwwroot

    # Verbose mode
    .\filescanner.ps1 -SearchRoot C:\Users\John\Documents -Verbose

    # Custom output
    .\filescanner.ps1 -SearchRoot C:\Projects -OutputFile results\scan.txt

    # Remote execution via IEX
    IEX (New-Object Net.WebClient).DownloadString('https://your-server/filescanner.ps1')
    Invoke-FileScanner -SearchRoot C:\inetpub\wwwroot -Verbose

CONFIG FILE FORMAT:
    [Section Name]
    Command: grep -r -i -E 'KEYWORDS' "`$SEARCH_ROOT" EXTENSIONS
    Example: [Auto-updated]
    Keywords: password, secret, token
    Extensions: *.txt, *.conf
    Files: id_rsa, *.pem

"@
}

if ($Help) {
    Show-Help
    exit 0
}

# Main scanner class
class FileScanner {
    [string]$ConfigFile
    [string]$SearchRoot
    [string]$OutputFile
    [bool]$IsVerbose
    [hashtable]$SectionExamples

    FileScanner([string]$config, [string]$root, [string]$output, [bool]$verbose) {
        $this.ConfigFile = $config
        $this.SearchRoot = $root
        $this.OutputFile = $output
        $this.IsVerbose = $verbose
        $this.SectionExamples = @{}
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
                
                # Check extension filter
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
                
                # Search file contents
                try {
                    $lineNum = 0
                    Get-Content -Path $file.FullName -ErrorAction SilentlyContinue | ForEach-Object {
                        $lineNum++
                        if ($regex.IsMatch($_)) {
                            $results += "$($file.FullName):$($lineNum):$_"
                        }
                    }
                } catch {
                    # Skip files we can't read
                }
            }
        } catch {
            if ($this.IsVerbose) {
                $this.Log("Error during search: $_", $true)
            }
        }
        
        return $results
    }

    [string[]]FindFiles([string[]]$patterns, [string[]]$namePatterns) {
        $results = @()
        
        try {
            Get-ChildItem -Path $this.SearchRoot -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
                $file = $_
                
                # Check patterns (extensions)
                if ($patterns) {
                    foreach ($pattern in $patterns) {
                        if ($file.Name -like $pattern) {
                            $results += $file.FullName
                            return
                        }
                    }
                }
                
                # Check name patterns
                if ($namePatterns) {
                    foreach ($pattern in $namePatterns) {
                        if ($file.Name -like $pattern) {
                            $results += $file.FullName
                            return
                        }
                    }
                }
            }
        } catch {
            if ($this.IsVerbose) {
                $this.Log("Error during find: $_", $true)
            }
        }
        
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
            } catch {
                # Skip files we can't read
            }
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
        
        # Replace KEYWORDS
        if ($keywords -and $keywords.Count -gt 0 -and $actualCommand -match 'KEYWORDS') {
            $keywordPattern = $keywords -join '|'
            $actualCommand = $actualCommand -replace 'KEYWORDS', $keywordPattern
        }
        
        # Replace EXTENSIONS placeholder
        if ($extensions -and $extensions.Count -gt 0 -and $actualCommand -match 'EXTENSIONS') {
            # For PowerShell commands (Get-ChildItem, Select-String)
            if ($actualCommand -match 'Get-ChildItem|Select-String') {
                # Format: -Include ext1,ext2,ext3
                $includeList = $extensions -join ','
                $actualCommand = $actualCommand -replace 'EXTENSIONS', "-Include $includeList"
            }
            # For grep commands (backward compatibility)
            elseif ($actualCommand -match 'grep') {
                $includeFlags = ($extensions | ForEach-Object { "--include=`"$_`"" }) -join ' '
                $actualCommand = $actualCommand -replace 'EXTENSIONS', $includeFlags
            }
            # For find commands (backward compatibility)
            elseif ($actualCommand -match 'find') {
                $nameFlags = '\( ' + (($extensions | ForEach-Object { "-name `"$_`"" }) -join ' -o ') + ' \)'
                $actualCommand = $actualCommand -replace 'EXTENSIONS', $nameFlags
            }
        }
        
        # Replace FILES placeholder
        if ($files -and $files.Count -gt 0 -and $actualCommand -match 'FILES') {
            # For PowerShell commands
            if ($actualCommand -match 'Get-ChildItem') {
                # Format: -Include file1,file2,file3
                $includeList = $files -join ','
                $actualCommand = $actualCommand -replace 'FILES', "-Include $includeList"
            }
            # For find commands (backward compatibility)
            elseif ($actualCommand -match 'find') {
                $nameFlags = '\( ' + (($files | ForEach-Object { "-name `"$_`"" }) -join ' -o ') + ' \)'
                $actualCommand = $actualCommand -replace 'FILES', $nameFlags
            }
        }
        
        return $actualCommand
    }

    [void]ExecuteSection([string]$sectionName, [string]$windowsCommand, [string]$linuxCommand, [string[]]$keywords, [string[]]$extensions, [string[]]$files) {
        $this.Log("`n=== $sectionName ===", $false)
        
        # Use Windows command, build example
        $actualCommand = $this.BuildActualCommand($windowsCommand, $keywords, $extensions, $files)
        $this.SectionExamples[$sectionName] = $actualCommand
        
        if ($this.IsVerbose) {
            $this.Log("Windows Command: $windowsCommand", $true)
            if ($keywords) { $this.Log("Keywords: $($keywords -join ', ')", $true) }
            if ($extensions) { $this.Log("Extensions: $($extensions -join ', ')", $true) }
            if ($files) { $this.Log("Files: $($files -join ', ')", $true) }
        }
        
        # Execute search based on command type
        $results = @()
        
        # Determine command type and execute
        if ($windowsCommand -match 'Select-String') {
            # PowerShell Select-String (equivalent to grep)
            if ($keywords) {
                $pattern = $keywords -join '|'
                $results = $this.SearchFiles($pattern, $extensions)
            }
        } elseif ($windowsCommand -match 'Get-ChildItem.*Get-Content') {
            # Find and display contents
            $patterns = if ($files) { $files } else { $extensions }
            $results = $this.FindAndCatFiles($patterns)
        } elseif ($windowsCommand -match 'Get-ChildItem') {
            # Simple file find
            if ($extensions) {
                $results = $this.FindFiles($extensions, $null)
            } elseif ($files) {
                $results = $this.FindFiles($null, $files)
            }
        }
        # Backward compatibility for old format
        elseif ($windowsCommand -match 'grep') {
            if ($keywords) {
                $pattern = $keywords -join '|'
                $results = $this.SearchFiles($pattern, $extensions)
            }
        } elseif ($windowsCommand -match 'find' -and $windowsCommand -match '-exec cat') {
            $patterns = if ($files) { $files } else { $extensions }
            $results = $this.FindAndCatFiles($patterns)
        } elseif ($windowsCommand -match 'find') {
            if ($extensions) {
                $results = $this.FindFiles($extensions, $null)
            } elseif ($files) {
                $results = $this.FindFiles($null, $files)
            }
        }
        
        # Output results
        if ($this.IsVerbose) {
            $this.Log("`n> Running search...", $true)
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
        
        Get-Content -Path $this.ConfigFile | ForEach-Object {
            $line = $_.Trim()
            
            # Skip empty lines and comments
            if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) {
                return
            }
            
            # Section header
            if ($line -match '^\[(.+)\]$') {
                if ($currentSection) {
                    $sections += $currentSection
                }
                $currentSection = @{
                    Name = $matches[1]
                    WindowsCommand = ''
                    LinuxCommand = ''
                    Keywords = @()
                    Extensions = @()
                    Files = @()
                }
                return
            }
            
            # Parse metadata - prioritize Windows command
            if ($line -match '^Windows Command:\s*(.+)$') {
                $currentSection.WindowsCommand = $matches[1].Trim()
            } elseif ($line -match '^Linux Command:\s*(.+)$') {
                $currentSection.LinuxCommand = $matches[1].Trim()
            } elseif ($line -match '^Command:\s*(.+)$') {
                # Backward compatibility - if no Windows/Linux split, use for both
                $cmd = $matches[1].Trim()
                if (-not $currentSection.WindowsCommand) {
                    $currentSection.WindowsCommand = $cmd
                }
                if (-not $currentSection.LinuxCommand) {
                    $currentSection.LinuxCommand = $cmd
                }
            } elseif ($line -match '^(Windows Example|Linux Example|Example):') {
                # Skip example lines, they'll be updated
            } elseif ($line -match '^Keywords:\s*(.+)$') {
                $currentSection.Keywords = $this.ParseList($matches[1])
            } elseif ($line -match '^Extensions:\s*(.+)$') {
                $currentSection.Extensions = $this.ParseList($matches[1])
            } elseif ($line -match '^Files:\s*(.+)$') {
                $currentSection.Files = $this.ParseList($matches[1])
            }
        }
        
        # Add last section
        if ($currentSection) {
            $sections += $currentSection
        }
        
        return $sections
    }

    [void]UpdateConfigFile() {
        $tempConfig = @()
        $currentSection = $null
        
        Get-Content -Path $this.ConfigFile | ForEach-Object {
            $line = $_
            
            # Track current section
            if ($line -match '^\[(.+)\]$') {
                $currentSection = $matches[1]
                $tempConfig += $line
            } elseif ($line -match '^Windows Example:') {
                # Replace Windows example line with updated command
                if ($this.SectionExamples.ContainsKey($currentSection)) {
                    $tempConfig += "Windows Example: $($this.SectionExamples[$currentSection])"
                } else {
                    $tempConfig += $line
                }
            } else {
                # Keep all other lines as-is (including Linux Example)
                $tempConfig += $line
            }
        }
        
        # Write back to file
        $tempConfig | Set-Content -Path $this.ConfigFile
    }

    [void]Run() {
        # Create output directory
        $outputDir = Split-Path -Parent $this.OutputFile
        if ($outputDir -and -not (Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
        
        # Write header
        $header = @(
            "Starting search from: $($this.SearchRoot)"
            "Config: $($this.ConfigFile)"
            "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            "=" * 40
        )
        $header | Set-Content -Path $this.OutputFile
        
        if ($this.IsVerbose) {
            $header | ForEach-Object { Write-Host $_ }
        }
        
        # Parse and execute sections
        $sections = $this.ParseConfig()
        foreach ($section in $sections) {
            if ($section.WindowsCommand -or $section.Command) {
                $this.ExecuteSection(
                    $section.Name,
                    $(if ($section.WindowsCommand) { $section.WindowsCommand } else { $section.Command }),
                    $(if ($section.LinuxCommand) { $section.LinuxCommand } else { $section.Command }),
                    $section.Keywords,
                    $section.Extensions,
                    $section.Files
                )
            }
        }
        
        # Footer
        $footer = @(
            ""
            "=" * 40
            "Completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        )
        $footer | Add-Content -Path $this.OutputFile
        
        if ($this.IsVerbose) {
            $footer | ForEach-Object { Write-Host $_ }
            Write-Host "Config file updated with actual commands"
        }
        
        Write-Host "Results saved to: $($this.OutputFile)" -ForegroundColor Green
        
        # Update config file
        $this.UpdateConfigFile()
    }
}

# Function for IEX remote execution
function Invoke-FileScanner {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SearchRoot,
        
        [Parameter(Mandatory=$false)]
        [string]$ConfigFile = ".\filescanner.config",
        
        [Parameter(Mandatory=$false)]
        [string]$OutputFile = "findings_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt",
        
        [Parameter(Mandatory=$false)]
        [switch]$Verbose
    )
    
    # Validate inputs
    if (-not (Test-Path $SearchRoot)) {
        Write-Error "Search root does not exist: $SearchRoot"
        return
    }
    
    if (-not (Test-Path $ConfigFile)) {
        Write-Error "Config file not found: $ConfigFile"
        return
    }
    
    # Create and run scanner
    $scanner = [FileScanner]::new($ConfigFile, $SearchRoot, $OutputFile, $Verbose.IsPresent)
    
    try {
        $scanner.Run()
    } catch {
        Write-Error "Error during scan: $_"
    }
}

# Main execution when run directly
if ($PSCmdlet.MyInvocation.InvocationName -ne '.') {
    # Validate search root
    if (-not (Test-Path $SearchRoot)) {
        Write-Error "Search root does not exist: $SearchRoot"
        exit 1
    }
    
    if (-not (Test-Path $ConfigFile)) {
        Write-Error "Config file not found: $ConfigFile"
        Write-Host "Run '.\filescanner.ps1 -Help' for usage information"
        exit 1
    }
    
    # Run scanner
    $scanner = [FileScanner]::new($ConfigFile, $SearchRoot, $OutputFile, $Verbose.IsPresent)
    
    try {
        $scanner.Run()
    } catch {
        Write-Error "Error during scan: $_"
        exit 1
    }
}

# Export function for module usage
Export-ModuleMember -Function Invoke-FileScanner