#!/bin/bash

# Argument check
if [ $# -ne 2 ]; then
    echo "Usage: $0 directory_name output_file_name"
    exit 1
fi

SOURCE_DIR="$1"
OUTPUT_FILE="$2"

# Check if directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: $SOURCE_DIR is not a valid directory."
    exit 1
fi

# Initialize the output file
> "$OUTPUT_FILE"

# Write the contents of each file in the directory to the output file
for FILE in "$SOURCE_DIR"/*; do
    if [ -f "$FILE" ]; then
        echo "File name: $FILE" >> "$OUTPUT_FILE"  # Output the file name
        cat "$FILE" >> "$OUTPUT_FILE"               # Output the file contents
        echo "" >> "$OUTPUT_FILE"                   # Add a newline
    fi
done

echo "The contents of the files have been written to $OUTPUT_FILE."
