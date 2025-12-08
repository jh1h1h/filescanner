#!/usr/bin/env python3
"""
Cross-platform file scanner for sensitive files and keywords.
Works on both Windows and Linux.
"""

import os
import sys
import argparse
import re
import subprocess
from datetime import datetime
from pathlib import Path
import fnmatch
import shutil


class FileScanner:
    def __init__(self, config_file, search_root, output_file, verbose=False):
        self.config_file = Path(config_file)
        self.search_root = Path(search_root)
        self.output_file = Path(output_file)
        self.verbose = verbose
        self.section_examples = {}
        
    def log(self, message, to_file=True, to_console=None):
        """Log message to file and optionally to console."""
        if to_console is None:
            to_console = self.verbose
            
        if to_console:
            print(message)
        if to_file:
            with open(self.output_file, 'a', encoding='utf-8') as f:
                f.write(message + '\n')
    
    def grep_files(self, pattern, extensions=None):
        """
        Search for pattern in files (cross-platform grep alternative).
        
        Args:
            pattern: Regex pattern to search for
            extensions: List of file extensions to include (e.g., ['*.txt', '*.conf'])
        """
        results = []
        
        try:
            for root, dirs, files in os.walk(self.search_root):
                for file in files:
                    # Check if file matches any extension pattern
                    if extensions:
                        if not any(fnmatch.fnmatch(file, ext) for ext in extensions):
                            continue
                    
                    filepath = Path(root) / file
                    try:
                        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                            for line_num, line in enumerate(f, 1):
                                if re.search(pattern, line, re.IGNORECASE):
                                    results.append(f"{filepath}:{line_num}:{line.rstrip()}")
                    except (PermissionError, OSError):
                        # Skip files we can't read
                        continue
        except Exception as e:
            if self.verbose:
                self.log(f"Error during grep: {e}")
        
        return results
    
    def find_files(self, patterns=None, name_patterns=None):
        """
        Find files matching patterns (cross-platform find alternative).
        
        Args:
            patterns: List of extension patterns (e.g., ['*.conf', '*.bak'])
            name_patterns: List of name patterns (e.g., ['*password*', 'id_rsa'])
        """
        results = []
        
        try:
            for root, dirs, files in os.walk(self.search_root):
                for file in files:
                    filepath = Path(root) / file
                    
                    # Check extension patterns
                    if patterns:
                        if any(fnmatch.fnmatch(file, pattern) for pattern in patterns):
                            results.append(str(filepath))
                            continue
                    
                    # Check name patterns
                    if name_patterns:
                        if any(fnmatch.fnmatch(file, pattern) for pattern in name_patterns):
                            results.append(str(filepath))
        except Exception as e:
            if self.verbose:
                self.log(f"Error during find: {e}")
        
        return results
    
    def find_and_cat_files(self, name_patterns):
        """Find files and output their contents."""
        results = []
        files_found = self.find_files(name_patterns=name_patterns)
        
        for filepath in files_found:
            try:
                with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read()
                    if content.strip():  # Only include non-empty files
                        results.append(f"=== {filepath} ===")
                        results.append(content)
            except (PermissionError, OSError):
                continue
        
        return results
    
    def parse_list(self, value):
        """Parse comma-separated list, trimming whitespace."""
        if not value:
            return []
        return [item.strip() for item in value.split(',')]
    
    def build_actual_command(self, command, keywords, extensions, files):
        """Build the actual command that would be executed."""
        actual_command = command
        
        # Replace KEYWORDS placeholder
        if keywords and 'KEYWORDS' in actual_command:
            keyword_pattern = '|'.join(keywords)
            actual_command = actual_command.replace('KEYWORDS', keyword_pattern)
        
        # Replace EXTENSIONS placeholder
        if extensions and 'EXTENSIONS' in actual_command:
            if 'grep' in actual_command:
                include_flags = ' '.join([f'--include="{ext}"' for ext in extensions])
                actual_command = actual_command.replace('EXTENSIONS', include_flags)
            elif 'find' in actual_command:
                name_flags = '\\( ' + ' -o '.join([f'-name "{ext}"' for ext in extensions]) + ' \\)'
                actual_command = actual_command.replace('EXTENSIONS', name_flags)
        
        # Replace FILES placeholder
        if files and 'FILES' in actual_command:
            name_flags = '\\( ' + ' -o '.join([f'-name "{f}"' for f in files]) + ' \\)'
            actual_command = actual_command.replace('FILES', name_flags)
        
        return actual_command
    
    def execute_section(self, section_name, command, keywords, extensions, files):
        """Execute a search section."""
        self.log(f"\n=== {section_name} ===")
        
        # Build example command for config update
        actual_command = self.build_actual_command(command, keywords, extensions, files)
        self.section_examples[section_name] = actual_command.replace('\\\\', '\\')
        
        if self.verbose:
            self.log(f"Command template: {command}")
            if keywords:
                self.log(f"Keywords: {', '.join(keywords)}")
            if extensions:
                self.log(f"Extensions: {', '.join(extensions)}")
            if files:
                self.log(f"Files: {', '.join(files)}")
        
        # Execute the appropriate search based on command type
        results = []
        
        if 'grep' in command:
            # Grep-based search
            if keywords:
                pattern = '|'.join(keywords)
                results = self.grep_files(pattern, extensions if extensions else None)
        
        elif 'find' in command and '-exec cat' in command:
            # Find files and cat their contents
            results = self.find_and_cat_files(files if files else extensions)
        
        elif 'find' in command:
            # Simple find
            if extensions:
                results = self.find_files(patterns=extensions)
            elif files:
                results = self.find_files(name_patterns=files)
        
        # Output results
        if self.verbose:
            self.log(f"\n> Running search...")
        
        if results:
            for result in results:
                self.log(result, to_console=self.verbose)
        elif self.verbose:
            self.log("No matches found")
    
    def parse_config(self):
        """Parse the configuration file."""
        sections = []
        current_section = {}
        
        with open(self.config_file, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.rstrip()
                
                # Skip empty lines and comments
                if not line or line.startswith('#'):
                    continue
                
                # Section header
                if line.startswith('[') and line.endswith(']'):
                    if current_section:
                        sections.append(current_section)
                    current_section = {
                        'name': line[1:-1],
                        'command': '',
                        'keywords': [],
                        'extensions': [],
                        'files': []
                    }
                    continue
                
                # Parse metadata lines
                if line.startswith('Command: '):
                    current_section['command'] = line[9:].strip()
                elif line.startswith('Example: '):
                    # We'll update this later
                    pass
                elif line.startswith('Keywords: '):
                    current_section['keywords'] = self.parse_list(line[10:])
                elif line.startswith('Extensions: '):
                    current_section['extensions'] = self.parse_list(line[12:])
                elif line.startswith('Files: '):
                    current_section['files'] = self.parse_list(line[7:])
        
        # Add last section
        if current_section:
            sections.append(current_section)
        
        return sections
    
    def update_config_file(self):
        """Update the config file with new example commands."""
        temp_config = []
        current_section = None
        
        with open(self.config_file, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.rstrip()
                
                # Track current section
                if line.startswith('[') and line.endswith(']'):
                    current_section = line[1:-1]
                    temp_config.append(line)
                elif line.startswith('Example: '):
                    # Replace with updated example
                    if current_section in self.section_examples:
                        temp_config.append(f"Example: {self.section_examples[current_section]}")
                    else:
                        temp_config.append(line)
                else:
                    temp_config.append(line)
        
        # Write back to file
        with open(self.config_file, 'w', encoding='utf-8') as f:
            f.write('\n'.join(temp_config) + '\n')
    
    def run(self):
        """Main execution method."""
        # Create output directory if needed
        self.output_file.parent.mkdir(parents=True, exist_ok=True)
        
        # Write header
        with open(self.output_file, 'w', encoding='utf-8') as f:
            f.write(f"Starting search from: {self.search_root}\n")
            f.write(f"Config: {self.config_file}\n")
            f.write(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write("=" * 40 + "\n")
        
        if self.verbose:
            print(f"Starting search from: {self.search_root}")
            print(f"Config: {self.config_file}")
            print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
            print("=" * 40)
        
        # Parse and execute sections
        sections = self.parse_config()
        for section in sections:
            if section['command']:
                self.execute_section(
                    section['name'],
                    section['command'],
                    section['keywords'],
                    section['extensions'],
                    section['files']
                )
        
        # Footer
        self.log("\n" + "=" * 40)
        self.log(f"Completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        
        # Update config file
        self.update_config_file()
        
        if self.verbose:
            print("Config file updated with actual commands")
        
        print(f"Results saved to: {self.output_file}")


def main():
    parser = argparse.ArgumentParser(
        description='Recursively search filesystem for sensitive files and keywords based on config file.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
EXAMPLES:
    # Search /var/www with default config (quiet mode)
    python filescanner.py -r /var/www

    # Verbose mode - shows commands and metadata
    python filescanner.py -r /var/www -v

    # Specify all parameters
    python filescanner.py -c my_config.txt -r /home/user -o results/scan.txt

CONFIG FILE FORMAT:
    [Section Name]
    Command: command_with_KEYWORDS_EXTENSIONS_FILES_placeholders
    Example: actual_command_example (auto-updated each run)
    Keywords: keyword1, keyword2, keyword3
    Extensions: *.ext1, *.ext2
    Files: file1, file2
    
    Placeholders:
    - KEYWORDS: Replaced with pipe-separated keywords
    - EXTENSIONS: Replaced with extension patterns
    - FILES: Replaced with file name patterns

OUTPUT:
    Without -v: Only matching results are saved
    With -v: Commands, metadata, and results are saved
        """
    )
    
    parser.add_argument('-c', '--config', default='./filescanner.config',
                        help='Path to config file (default: ./filescanner.config)')
    parser.add_argument('-r', '--root', required=True,
                        help='Root directory to search from (REQUIRED)')
    parser.add_argument('-o', '--output',
                        default=f"findings_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt",
                        help='Path to output file (default: findings_YYYYMMDD_HHMMSS.txt)')
    parser.add_argument('-v', '--verbose', action='store_true',
                        help='Show commands being run and metadata (default: off)')
    
    args = parser.parse_args()
    
    # Validate inputs
    search_root = Path(args.root)
    if not search_root.exists():
        print(f"Error: Search root directory does not exist: {search_root}")
        sys.exit(1)
    
    if not search_root.is_dir():
        print(f"Error: Search root is not a directory: {search_root}")
        sys.exit(1)
    
    config_file = Path(args.config)
    if not config_file.exists():
        print(f"Config file not found: {config_file}")
        print("Run 'python filescanner.py --help' for usage information")
        sys.exit(1)
    
    # Create and run scanner
    scanner = FileScanner(
        config_file=args.config,
        search_root=args.root,
        output_file=args.output,
        verbose=args.verbose
    )
    
    try:
        scanner.run()
    except KeyboardInterrupt:
        print("\n\nScan interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\nError during scan: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()