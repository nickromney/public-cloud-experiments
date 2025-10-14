#!/usr/bin/env bash
#
# Fix MD029: Ordered list prefixes should all be "1."
#
# Usage: ./fix-ordered-lists.sh [file or directory]
#

set -euo pipefail

fix_file() {
    local file=$1

    # Replace numbered list items (2., 3., 4., etc.) with 1.
    # This matches lines starting with optional whitespace, a number > 1, and a period
    if grep -qE '^[[:space:]]*[2-9][0-9]*\.' "$file"; then
        sed -i '' -E 's/^([[:space:]]*)([2-9][0-9]*)\./\11./' "$file"
        echo "Fixed: $file"
    fi
}

if [[ -d "${1:-}" ]]; then
    find "$1" -name "*.md" -type f | while read -r file; do
        fix_file "$file"
    done
elif [[ -f "${1:-}" ]]; then
    fix_file "$1"
else
    echo "Usage: $0 <file-or-directory>"
    exit 1
fi
