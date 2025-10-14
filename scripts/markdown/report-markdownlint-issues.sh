#!/usr/bin/env bash
#
# Report markdown linting issues grouped by file and type
#
# Usage: ./report-markdownlint-issues.sh [directory]
#

set -euo pipefail

TARGET_DIR="${1:-documentation}"
TEMP_FILE="/tmp/markdownlint-report.$$"

echo "Markdown Linting Report for: $TARGET_DIR"
echo "=========================================="
echo ""

# Run markdownlint and save to temp file
markdownlint -c .markdownlint.yaml "$TARGET_DIR/**/*.md" > "$TEMP_FILE" 2>&1 || true

# Check if there are any issues
if [[ ! -s "$TEMP_FILE" ]]; then
    echo "✓ No markdown linting issues found!"
    rm -f "$TEMP_FILE"
    exit 0
fi

# Get total count
total_issues=$(wc -l < "$TEMP_FILE" | tr -d ' ')
echo "Total issues: $total_issues"
echo ""

# Breakdown by issue type
echo "Issues by Type:"
echo "---------------"
awk '{print $2}' "$TEMP_FILE" | \
    sort | \
    uniq -c | \
    sort -rn | \
    awk '{printf "  %3d  %s\n", $1, $2}'
echo ""

# Files with issues
echo "Files Requiring Manual Intervention:"
echo "-------------------------------------"
cut -d':' -f1 "$TEMP_FILE" | \
    sort | \
    uniq -c | \
    sort -rn | \
    awk '{printf "  %2d issues: %s\n", $1, $2}'
echo ""

# Full details
echo "Detailed Issues:"
echo "----------------"
cat "$TEMP_FILE"

# Cleanup
rm -f "$TEMP_FILE"
