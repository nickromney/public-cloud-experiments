#!/usr/bin/env python3
"""Fix Step emphasis to proper headings in markdown files.

Converts **Step X: ...** to #### Step X: ...

Usage:
    ./fix-step-headings.py <file-or-directory>
"""

import re
import sys
from pathlib import Path


def fix_step_headings(text: str) -> str:
    """Convert Step emphasis to proper headings."""
    # Match **Step N: text** at start of line
    # Use ### for implementation plan steps (h3, not h4)
    text = re.sub(
        r"^\*\*Step (\d+): (.*?)\*\*$",
        r"### Step \1: \2",
        text,
        flags=re.MULTILINE,
    )
    # Also fix h4 Steps to h3
    text = re.sub(
        r"^#### Step (\d+): (.*?)$",
        r"### Step \1: \2",
        text,
        flags=re.MULTILINE,
    )
    return text


def process_file(file_path: Path) -> bool:
    """Process a single file, return True if modified."""
    content = file_path.read_text(encoding="utf-8")
    fixed = fix_step_headings(content)

    if content != fixed:
        file_path.write_text(fixed, encoding="utf-8")
        print(f"Fixed: {file_path}")
        return True

    return False


def main():
    if len(sys.argv) != 2:
        print("Usage: ./fix-step-headings.py <file-or-directory>")
        sys.exit(1)

    target = Path(sys.argv[1])

    if target.is_file():
        process_file(target)
    elif target.is_dir():
        for md_file in target.rglob("*.md"):
            process_file(md_file)
    else:
        print(f"Error: {target} is not a file or directory")
        sys.exit(1)


if __name__ == "__main__":
    main()
