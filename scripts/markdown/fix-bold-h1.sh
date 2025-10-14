#!/usr/bin/env bash
#
# Fix MD025: Convert bold text that looks like H1 headings to actual H2 headings
#
# Usage: ./fix-bold-h1.sh [file or directory]
#

set -euo pipefail

fix_file() {
    local file=$1
    local changed=false

    # Check if file has frontmatter with title
    if ! head -20 "$file" | grep -q "^title:"; then
        return
    fi

    # Convert lines like "**Text**" (bold text on its own line) to "## Text" (H2)
    # Only if they appear after the frontmatter
    if perl -0777 -ne 'print if /---\n.*?---\n.*?\*\*[^\*\n]+\*\*\s*$/sm' "$file" | grep -q '.*'; then
        # Use perl to find bold text after frontmatter and convert to H2
        perl -i -0pe 's/(---\n.*?---\n)(.*?)^\*\*([^\*\n]+)\*\*\s*$/\1\2## \3/gms' "$file"
        changed=true
    fi

    if [[ "$changed" == "true" ]]; then
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
