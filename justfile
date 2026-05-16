# Vyrox Documentation Justfile
# =====================================================================
# Production-grade task runner for documentation.
# Public docs: ARCHITECTURE.md, API_REFERENCE.md, QUICKSTART.md
#
# Usage:
#   just              # Show all commands
#   just <command>   # Run specific command
# =====================================================================

set shell := ["zsh", "-cu"]

# =====================================================================
# DEFAULT
# =====================================================================

default:
    @just --list

# =====================================================================
# DOCUMENTATION
# =====================================================================

# View ARCHITECTURE.md
view-architecture:
    @cat ARCHITECTURE.md

# View API reference
view-api:
    @cat API_REFERENCE.md

# View quickstart
view-quickstart:
    @cat QUICKSTART.md

# View all docs
view-all:
    @echo "=== ARCHITECTURE.md ==="
    @cat ARCHITECTURE.md
    @echo ""
    @echo "=== API_REFERENCE.md ==="
    @cat API_REFERENCE.md
    @echo ""
    @echo "=== QUICKSTART.md ==="
    @cat QUICKSTART.md

# =====================================================================
# LINK CHECKING
# =====================================================================

# Check for broken links (requires markdown-link-check)
check-links:
    @echo "Checking markdown links..."
    @grep -rh "\[.*\](.*\.md)" . --include="*.md" | grep -v "^\s*#" | while read line; do
      target=$(echo "$line" | sed 's/.*](\([^)]*\)).*/\1/')
      if [ -n "$target" ] && [ ! -f "$target" ]; then
        echo "Broken link: $target"
      fi
    done || true

# =====================================================================
# LINTING
# =====================================================================

# Lint markdown files
lint:
    @echo "Linting markdown files..."
    @for f in *.md; do
      if [ -f "$f" ]; then
        echo "Checking $f..."
        # Check for trailing whitespace
        grep -n "[[:space:]]$$" "$f" || true
        # Check for broken internal links
        grep -En "\]\([a-zA-Z_]*\.md\)" "$f" | while read line; do
          file=$(echo "$line" | sed 's/:.*//')
          link=$(echo "$line" | sed 's/.*](\([^)]*\)).*/\1/')
          if [ ! -f "$link" ]; then
            echo "$file: broken link [$link]"
          fi
        done
      fi
    done

# Check for TODO markers
check-todos:
    @grep -rn "TODO\|FIXME\|XXX\|HACK" . --include="*.md" || echo "No TODOs found"

# =====================================================================
# FORMATTING
# =====================================================================

# Format markdown (basic cleanup)
format:
    @echo "Formatting markdown files..."
    @for f in *.md; do
      if [ -f "$f" ]; then
        # Remove trailing whitespace
        sed -i 's/[[:space:]]*$$//' "$f"
        # Ensure single newline at end of file
        perl -i -pe 's/\n*\z/\n/' "$f"
      fi
    done

# =====================================================================
# WORD COUNT
# =====================================================================

# Count words in documentation
words:
    @echo "Word count by file:"
    @for f in *.md; do
      if [ -f "$f" ]; then
        count=$(wc -w < "$f")
        echo "  $f: $count words"
      fi
    done
    @echo ""
    @echo "Total: $(cat *.md | wc -w) words"

# Line count
lines:
    @echo "Line count by file:"
    @for f in *.md; do
      if [ -f "$f" ]; then
        count=$(wc -l < "$f")
        echo "  $f: $count lines"
      fi
    done

# =====================================================================
# CLEANUP
# =====================================================================

# Clean temporary files
clean:
    rm -f *.tmp
    rm -f *~

# =====================================================================
# CI/CD
# =====================================================================

# Check docs for CI
ci:
    just lint
    just check-todos

# =====================================================================
# HELP
# =====================================================================

help:
    @just --list --unsorted