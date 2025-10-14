#!/usr/bin/env bash
#
# Fix MD025: Remove duplicate H1 headings when title exists in frontmatter
#
# Usage: ./fix-duplicate-h1.sh [file or directory]
#

set -euo pipefail

fix_file() {
    local file=$1

    # Check if file has frontmatter with title
    if head -20 "$file" | grep -q "^title:"; then
        # Convert all H1 headings to H2 after frontmatter
        # This handles files where title is in frontmatter, so H1s should be H2s
        # Match: start of line, #, space, rest of line (including bold markers)
        perl -i -0pe 's/(---\n.*?---\n.*)^# (.+)$/\1## \2/msg' "$file"
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
