# Markdown Fixing Scripts

Scripts to automatically fix common markdown linting issues in documentation.

## Quick Start

```bash
# Run all fixes on documentation directory
./scripts/markdown/fix-all-docs.sh documentation
```

**Result**: Reduced issues from 97 to 24 (75% fixed automatically).

## Scripts

### `report-markdownlint-issues.sh` - Issue Report

Shows a summary of all markdown linting issues, grouped by type and file.

```bash
# Report on documentation directory
./report-markdownlint-issues.sh documentation

# Report on specific subdirectory
./report-markdownlint-issues.sh documentation/2024-07-19-upgrade-to-43
```

**Output includes:**

- Total issue count
- Breakdown by issue type (MD001, MD056, etc.)
- Files requiring manual intervention
- Full detailed list of all issues

### `fix-all-docs.sh` - Master Script

Runs all fixes in sequence and reports final issue count.

```bash
# Fix all documentation
./fix-all-docs.sh documentation

# Fix specific directory
./fix-all-docs.sh documentation/2024-07-06-rds-from-mysql-57-to-80
```

### `fix-duplicate-h1.sh`

Fixes **MD025**: Removes duplicate H1 headings when a title exists in frontmatter.

```bash
./fix-duplicate-h1.sh documentation
```

### `fix-bold-h1.sh`

Fixes **MD025**: Converts bold text that looks like H1 headings to actual H2 headings.

```bash
./fix-bold-h1.sh documentation
```

### `fix-image-alt-text.sh`

Fixes **MD045**: Adds default "Image" alt text to images missing it.

```bash
./fix-image-alt-text.sh documentation
```

### `fix-ordered-lists.sh`

Fixes **MD029**: Changes all numbered list items to use "1." prefix (markdown auto-numbers).

```bash
./fix-ordered-lists.sh documentation
```

### `remove-emojis.py`

Removes all emojis from markdown files (required for pre-commit compliance).

```bash
uv run scripts/markdown/remove-emojis.py documentation
```

## What Gets Fixed Automatically

These scripts fix 75% of markdown issues automatically:

- **MD022**: Blank lines around headings (via markdownlint --fix)
- **MD025**: Multiple H1 headings - **FULLY FIXED** (custom scripts)
- **MD026**: Trailing punctuation in headings (via markdownlint --fix)
- **MD029**: Ordered list numbering (custom script)
- **MD031**: Blank lines around fences (via markdownlint --fix)
- **MD032**: Blank lines around lists (via markdownlint --fix)
- **MD034**: Bare URLs (via markdownlint --fix)
- **MD036**: Emphasis used as heading (custom script)
- **MD040**: Missing code language specifiers (via markdownlint --fix)
- **MD045**: Missing image alt text (custom script)
- **MD051**: Some link fragments (markdownlint auto-lowercases)
- **Emojis**: All emoji characters removed (custom script)

## What Requires Manual Review (24 issues remaining)

These require human judgment or should be disabled in `.markdownlint.yaml`:

- **MD001** (10 issues): Heading level skips - docs have non-standard structure (e.g., H2 → H4 → H6)
- **MD022** (3 issues): Blank lines around headings - edge cases not auto-fixed
- **MD026** (1 issue): Trailing punctuation - edge case
- **MD031** (1 issue): Blank lines around fences - edge case
- **MD051** (5 issues): Invalid link fragments - Confluence-specific anchor format (`#GettingstartedinConfluence-Confluence101`)
- **MD056** (4 issues): Table column mismatch - tables need restructuring or escaping

## Workflow

1. Run auto-fixes:

   ```bash
   ./fix-all-docs.sh documentation
   ```

1. Review remaining issues:

   ```bash
   markdownlint -c .markdownlint.yaml 'documentation/**/*.md'
   ```

1. Manually fix structural issues that can't be automated

1. Commit clean documentation
