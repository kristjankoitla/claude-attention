#!/usr/bin/env python3
"""Render a template file by replacing placeholders with XML-escaped values."""
import sys
import xml.sax.saxutils


def main():
    if len(sys.argv) < 2 or (len(sys.argv) - 2) % 2 != 0:
        print(f"Usage: {sys.argv[0]} TEMPLATE [PLACEHOLDER VALUE]...", file=sys.stderr)
        sys.exit(1)

    with open(sys.argv[1]) as f:
        text = f.read()

    for i in range(2, len(sys.argv), 2):
        placeholder = sys.argv[i]
        value = xml.sax.saxutils.escape(sys.argv[i + 1], {'"': "&quot;"})
        text = text.replace(placeholder, value)

    sys.stdout.write(text)


if __name__ == "__main__":
    main()
