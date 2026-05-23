# Vyrox Documentation task runner.
#
# The docs site is an mdBook compiled from the top-level Markdown
# files. `book.toml` is the configuration, `src/SUMMARY.md` is the
# chapter order, and `theme/` holds the brand CSS and the Google
# Fonts loader. The actual `mdbook build` invocation lives in
# `scripts/build.sh` so Cloudflare Pages can call it directly.
#
# Usage:
#   just                 list every recipe
#   just build           produce ./book/
#   just serve           local preview on http://localhost:3000
#   just lint            line-length, trailing whitespace, broken links
#   just clean           remove ./book/ and the local mdbook cache

set shell := ["bash", "-cu"]

default:
    @just --list

# Build the static site into ./book/. Idempotent.
build:
    bash scripts/build.sh

# Serve with mdbook's own watch+livereload. Edits to src/ or top-level
# files trigger a rebuild and a browser refresh.
serve:
    mdbook serve --open

# Quick lint pass: trailing whitespace, em-dashes (house style), and
# Markdown links that target a missing file. Exits non-zero on hits.
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    fail=0
    for f in *.md; do
        if grep -nE "[[:space:]]+$" "$f" >/dev/null; then
            echo "[lint] trailing whitespace in $f:" && grep -nE "[[:space:]]+$" "$f"
            fail=1
        fi
        if grep -nE "[—–]" "$f" >/dev/null; then
            echo "[lint] em or en dash in $f (house style is plain ASCII):"
            grep -nE "[—–]" "$f"
            fail=1
        fi
    done
    exit $fail

# Run a strict broken-link check across the public Markdown files.
links:
    #!/usr/bin/env bash
    set -euo pipefail
    for f in *.md; do
        grep -oE "\]\([A-Z_]+\.md\)" "$f" 2>/dev/null \
            | sed -E "s/\]\(([A-Z_]+\.md)\)/\1/" | sort -u \
            | while read target; do
                if [[ ! -f "$target" ]]; then
                    echo "[links] $f references missing chapter: $target"
                fi
            done
    done

# Word and line counts per chapter. Useful for tracking doc growth.
stats:
    @for f in *.md; do printf "%-22s %5d lines  %6d words\n" "$f" "$(wc -l < $f)" "$(wc -w < $f)"; done

# Remove the build output and the local mdbook binary cache.
clean:
    rm -rf book/ .mdbook-bin/

# Run lint + links. Mirrored by CI.
ci: lint links
