#!/usr/bin/env bash
# build.sh — produce the static documentation site.
#
# Used by:
#   - Cloudflare Pages (build command: `bash scripts/build.sh`)
#   - Local contributors via `just build` or `npm run build`
#   - CI in `.github/workflows/build-docs.yml`
#
# What it does:
#   1. Make sure the chapter files in src/ are in sync with the canonical
#      top-level Markdown files. Top-level wins. We copy on every build
#      so a contributor who only edits the top-level file does not need
#      to remember src/.
#   2. Install mdbook if the host does not already have it. On Cloudflare
#      Pages the workspace is ephemeral so we always end up here.
#   3. Run `mdbook build`. Output lands in `book/`.
#
# Exit codes:
#   0   build succeeded
#   1   sync or build failed
#   2   environment is missing a required tool

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# ---------------------------------------------------------------------
# 1. Sync canonical top-level Markdown into src/
# ---------------------------------------------------------------------
# These are the files we publish. SUMMARY.md and the theme/ directory
# are mdBook-only and live in src/ + theme/ already.
CHAPTERS=(
    "README.md"
    "ARCHITECTURE.md"
    "THREAT_MODEL.md"
    "AUDIT_CHAIN.md"
    "API_REFERENCE.md"
    "ADAPTERS.md"
    "QUICKSTART.md"
    "CONTRIBUTING.md"
    "CODE_OF_CONDUCT.md"
    "SECURITY.md"
    "ROADMAP.md"
)

echo "[build] syncing $((${#CHAPTERS[@]})) chapters into src/"
for f in "${CHAPTERS[@]}"; do
    if [[ ! -f "$f" ]]; then
        echo "[build] missing top-level chapter: $f" >&2
        exit 1
    fi
    cp "$f" "src/$f"
done

# ---------------------------------------------------------------------
# 2. Make sure mdbook is available
# ---------------------------------------------------------------------
# Cloudflare Pages does not ship mdbook. We fetch the pinned release
# tarball if the binary is not on PATH. Pinning the version means a
# release-channel change on the upstream cannot break this build.
MDBOOK_VERSION="${MDBOOK_VERSION:-v0.4.40}"
LOCAL_MDBOOK_BIN="$REPO_ROOT/.mdbook-bin/mdbook"

mdbook_cmd() {
    if command -v mdbook >/dev/null 2>&1; then
        echo "mdbook"
        return
    fi
    if [[ -x "$LOCAL_MDBOOK_BIN" ]]; then
        echo "$LOCAL_MDBOOK_BIN"
        return
    fi
    echo ""
}

if [[ -z "$(mdbook_cmd)" ]]; then
    echo "[build] mdbook not found, installing ${MDBOOK_VERSION} locally"
    mkdir -p "$REPO_ROOT/.mdbook-bin"

    # Pick the right tarball for the current platform. Cloudflare Pages
    # runs Ubuntu x86_64, but a local contributor might run macOS. We
    # cover both and fail loudly on anything else.
    OS="$(uname -s)"
    ARCH="$(uname -m)"
    case "$OS-$ARCH" in
        Linux-x86_64)
            URL="https://github.com/rust-lang/mdBook/releases/download/${MDBOOK_VERSION}/mdbook-${MDBOOK_VERSION}-x86_64-unknown-linux-gnu.tar.gz"
            ;;
        Darwin-arm64)
            URL="https://github.com/rust-lang/mdBook/releases/download/${MDBOOK_VERSION}/mdbook-${MDBOOK_VERSION}-aarch64-apple-darwin.tar.gz"
            ;;
        Darwin-x86_64)
            URL="https://github.com/rust-lang/mdBook/releases/download/${MDBOOK_VERSION}/mdbook-${MDBOOK_VERSION}-x86_64-apple-darwin.tar.gz"
            ;;
        *)
            echo "[build] unsupported platform: $OS-$ARCH" >&2
            echo "[build] install mdbook manually and put it on PATH" >&2
            exit 2
            ;;
    esac

    echo "[build] fetching $URL"
    curl -sSL "$URL" | tar -xz -C "$REPO_ROOT/.mdbook-bin/"
    chmod +x "$REPO_ROOT/.mdbook-bin/mdbook"
fi

MDBOOK="$(mdbook_cmd)"
if [[ -z "$MDBOOK" ]]; then
    echo "[build] mdbook still not available after install attempt" >&2
    exit 2
fi

# ---------------------------------------------------------------------
# 3. Build
# ---------------------------------------------------------------------
echo "[build] running $MDBOOK build"
"$MDBOOK" build

# ---------------------------------------------------------------------
# 4. Copy Cloudflare Pages metadata into the build output
# ---------------------------------------------------------------------
# `_headers` and `_redirects` belong at the root of the deployed
# directory. They live at the repo root so a contributor reading the
# repo can see them, and we copy them in at the end of the build so
# Cloudflare Pages sees them in `book/`.
for f in _headers _redirects; do
    if [[ -f "$f" ]]; then
        cp "$f" "book/$f"
        echo "[build] copied $f into book/"
    fi
done

echo "[build] done; output in book/"
