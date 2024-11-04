#!/bin/bash

set -e

# ===================== Function Definitions =====================

# Check if required commands are available
function check_requirements() {
  local required_commands=("find" "uname" "awk" "jq")
  for cmd in "${required_commands[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
      echo "Error: '$cmd' command is required. Please install it." >&2
      exit 1
    fi
  done
}

# Get the relative path of a file
function get_relative_path() {
  local target_file="$1"
  local base_dir="$2"
  local rel_path="${target_file#$base_dir/}"
  echo "$rel_path"
}

# Directories to exclude
EXCLUDE_DIRS=(".venv" "node_modules" ".git")

# Generate find options for excluding directories
function generate_prune_expr() {
  local prune_expr=""
  for dir in "${EXCLUDE_DIRS[@]}"; do
    prune_expr="$prune_expr -path \"$project_dir/$dir\" -prune -o"
  done
  echo "$prune_expr"
}

# Collect code statistics
function collect_code_statistics() {
  echo "Collecting code statistics..."
  local code_stats_file="${output_dir}/code_statistics.txt"
  local prune_expr=$(generate_prune_expr)
  eval "find \"$project_dir\" $prune_expr -type f \( -name \"*.py\" -o -name \"*.js\" -o -name \"*.rb\" -o -name \"*.php\" -o -name \"*.java\" \) -exec wc -l {} +" > "$code_stats_file"
}

# Extract function and class definitions
function extract_code_definitions() {
  echo "Extracting code definitions..."
  local definitions_file="${output_dir}/code_definitions.json"
  echo "{" > "$definitions_file"

  local first_entry=true
  local prune_expr=$(generate_prune_expr)
  eval "find \"$project_dir\" $prune_expr -type f \( -name \"*.py\" -o -name \"*.js\" -o -name \"*.rb\" -o -name \"*.php\" -o -name \"*.java\" \) -print0" |
  while IFS= read -r -d '' file; do
    local rel_path=$(get_relative_path "$file" "$project_dir")
    local lang="${file##*.}"
    local definitions=""

    case "$lang" in
      py)
        definitions=$(grep -E '^\s*(def|class) ' "$file" | awk '{$1=$1;print}')
        ;;
      js)
        definitions=$(grep -E '^\s*(function|class) ' "$file" | awk '{$1=$1;print}')
        ;;
      php)
        definitions=$(grep -E '^\s*(function|class) ' "$file" | awk '{$1=$1;print}')
        ;;
      java)
        definitions=$(grep -E '^\s*(public|protected|private)?\s*(class|interface|enum|void|int|String|double|float|char|boolean|byte|short|long)\s+\w+' "$file" | awk '{$1=$1;print}')
        ;;
      rb)
        definitions=$(grep -E '^\s*(def|class|module) ' "$file" | awk '{$1=$1;print}')
        ;;
      *)
        definitions=""
        ;;
    esac

    if [ -n "$definitions" ]; then
      if [ "$first_entry" = true ]; then
        first_entry=false
      else
        echo "," >> "$definitions_file"
      fi
      echo "\"$rel_path\": [" >> "$definitions_file"
      echo "$definitions" | sed 's/"/\\"/g' | awk '{printf "  \"%s\",\n", $0}' | sed '$ s/,$//' >> "$definitions_file"
      echo "]" >> "$definitions_file"
    fi
  done

  echo "}" >> "$definitions_file"
}

# Extract documentation comments
function extract_docstrings() {
  echo "Extracting documentation comments..."
  local docstrings_file="${output_dir}/docstrings.json"
  echo "{" > "$docstrings_file"

  local first_entry=true
  local prune_expr=$(generate_prune_expr)
  eval "find \"$project_dir\" $prune_expr -type f \( -name \"*.py\" -o -name \"*.js\" -o -name \"*.rb\" -o -name \"*.php\" -o -name \"*.java\" \) -print0" |
  while IFS= read -r -d '' file; do
    local rel_path=$(get_relative_path "$file" "$project_dir")
    local lang="${file##*.}"
    local docstrings=""

    case "$lang" in
      py)
        docstrings=$(awk "
          BEGIN { flag=0; doc=\"\" }
          /^\s*(\"\"\"|''')/ { flag=1; doc=\$0; next }
          flag {
            doc = doc \"\\n\" \$0
            if (\$0 ~ /(\"\"\"|''')\$/) {
              print doc; flag=0; doc=\"\"
            }
          }
        " "$file")
        ;;
      js|php|java)
        docstrings=$(awk "
          BEGIN { flag=0; doc=\"\" }
          /^\s*\/\*\*/ { flag=1; doc=\$0; next }
          flag {
            doc = doc \"\\n\" \$0
            if (\$0 ~ /\*\/\$/) {
              print doc; flag=0; doc=\"\"
            }
          }
        " "$file")
        ;;
      rb)
        docstrings=$(awk "
          BEGIN { flag=0; doc=\"\" }
          /^=begin/ { flag=1; doc=\$0; next }
          flag {
            doc = doc \"\\n\" \$0
            if (\$0 ~ /^=end\$/) {
              print doc; flag=0; doc=\"\"
            }
          }
        " "$file")
        ;;
      *)
        docstrings=""
        ;;
    esac

    if [ -n "$docstrings" ]; then
      if [ "$first_entry" = true ]; then
        first_entry=false
      else
        echo "," >> "$docstrings_file"
      fi
      echo "\"$rel_path\": [" >> "$docstrings_file"
      echo "$docstrings" | sed 's/"/\\"/g' | awk '{printf "  \"%s\",\n", $0}' | sed '$ s/,$//' >> "$docstrings_file"
      echo "]" >> "$docstrings_file"
    fi
  done

  echo "}" >> "$docstrings_file"
}

# Collect dependency information
function collect_dependencies() {
  echo "Collecting dependency information..."
  local dependencies_file="${output_dir}/dependencies.txt"

  if [ -f "$project_dir/requirements.txt" ]; then
    echo "Python dependencies (from requirements.txt):" > "$dependencies_file"
    cat "$project_dir/requirements.txt" >> "$dependencies_file"
  elif [ -f "$project_dir/Pipfile" ]; then
    echo "Python dependencies (from Pipfile):" > "$dependencies_file"
    cat "$project_dir/Pipfile" >> "$dependencies_file"
  fi

  if [ -f "$project_dir/package.json" ]; then
    echo "JavaScript dependencies (from package.json):" >> "$dependencies_file"
    jq '.dependencies' "$project_dir/package.json" >> "$dependencies_file"
  fi

  if [ -f "$project_dir/Gemfile" ]; then
    echo "Ruby dependencies (from Gemfile):" >> "$dependencies_file"
    cat "$project_dir/Gemfile" >> "$dependencies_file"
  fi

  if [ -f "$project_dir/composer.json" ]; then
    echo "PHP dependencies (from composer.json):" >> "$dependencies_file"
    jq '.require' "$project_dir/composer.json" >> "$dependencies_file"
  fi
}

# Collect technical information
function collect_technical_info() {
  echo "## Technical Information"
  echo "### Languages and Versions"
  for lang in python python2 python3 node ruby php java; do
    if command -v "$lang" > /dev/null 2>&1; then
      version_info=$("$lang" --version 2>&1 | head -n 1)
      echo "- $lang: $version_info"
    fi
  done
  echo ""
}

# Display help message
function display_help() {
  echo "Usage: $0 [options] <project_directory>"
  echo ""
  echo "Options:"
  echo "  -h               Display help"
  echo "  -d <directory>   Specify the project directory"
  echo "  -o <directory>   Specify the output directory"
  exit 0
}

# ===================== Main Process =====================

# Parse options
while getopts ":hd:o:" opt; do
  case $opt in
    h)
      display_help
      ;;
    d)
      project_dir="$OPTARG"
      ;;
    o)
      output_dir="$OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

shift $((OPTIND -1))

# Get project directory
if [ -z "$project_dir" ]; then
  project_dir="$1"
fi

# Error check: No argument specified
if [ -z "$project_dir" ]; then
  echo "Error: Project directory must be specified." >&2
  echo "Usage: $0 <project_directory>" >&2
  exit 1
fi

# Error check: Specified directory does not exist
if [ ! -d "$project_dir" ]; then
  echo "Error: Directory '$project_dir' does not exist." >&2
  exit 1
fi

# Convert to absolute path
project_dir="$(cd "$project_dir"; pwd)"

# Set output directory
if [ -z "$output_dir" ]; then
  output_dir="${project_dir}/project_analysis"
fi

# Create output directory
mkdir -p "$output_dir"

# Check if required commands are available
check_requirements

# Collect technical information
echo "Collecting technical information..."
collect_technical_info > "${output_dir}/technical_info.txt"

# Collect code statistics
collect_code_statistics

# Extract code definitions
extract_code_definitions

# Extract documentation comments
extract_docstrings

# Collect dependency information
collect_dependencies

# Get project overview
if [ -f "$project_dir/README.md" ]; then
  cp "$project_dir/README.md" "${output_dir}/README.md"
fi

echo "Analysis complete. Output directory: $output_dir"

exit 0
