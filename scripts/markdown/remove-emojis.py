#!/usr/bin/env python3
"""Remove emojis from markdown files.

Usage:
    ./remove-emojis.py <file-or-directory>
"""

import re
import sys
from pathlib import Path


# Emoji regex pattern covering common ranges
EMOJI_PATTERN = re.compile(
    "["
    "\U0001F300-\U0001FAF6"  # Emoticons & symbols
    "\U00002600-\U000026FF"  # Misc symbols
    "\U00002700-\U000027BF"  # Dingbats
    "\U00002B00-\U00002BFF"  # Misc symbols and pictographs (includes stars)
    "\U0000231A-\U000023FF"  # Misc technical
    "\U0000FE00-\U0000FE0F"  # Variation selectors
    "]+",
    flags=re.UNICODE,
)


def remove_emojis(text: str) -> str:
    """Remove all emoji characters from text."""
    # Remove emojis
    text = EMOJI_PATTERN.sub("", text)
    # Clean up multiple spaces left by emoji removal
    text = re.sub(r"  +", " ", text)
    return text


def process_file(file_path: Path) -> bool:
    """Process a single file, return True if modified."""
    content = file_path.read_text(encoding="utf-8")
    cleaned = remove_emojis(content)

    if content != cleaned:
        file_path.write_text(cleaned, encoding="utf-8")
        print(f"Fixed: {file_path}")
        return True

    return False


def main():
    if len(sys.argv) != 2:
        print("Usage: ./remove-emojis.py <file-or-directory>")
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
