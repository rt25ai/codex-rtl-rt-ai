#!/bin/bash
# ============================================================================
# RT-AI Codex RTL Patch - Online uninstaller for macOS
#
# Run via:
#   curl -fsSL https://raw.githubusercontent.com/rt25ai/codex-rtl-rt-ai/main/uninstall-online.sh | bash
# ============================================================================
set -euo pipefail

REPO="${RT_AI_CODEX_REPO:-rt25ai/codex-rtl-rt-ai}"
BRANCH="${RT_AI_CODEX_BRANCH:-v0.2.0}"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

log()     { printf "  ${CYAN}[*]${NC} %s\n" "$1"; }
success() { printf "  ${GREEN}[+]${NC} %s\n" "$1"; }
step()    { printf "\n${BOLD}${CYAN}==> %s${NC}\n" "$1"; }
die()     { printf "  ${RED}[X]${NC} %s\n" "$1" >&2; exit 1; }

printf "\n============================================================\n"
printf "  RT-AI Codex RTL Patch - Online Uninstaller (macOS)\n"
printf "  https://rt-ai.co.il\n"
printf "============================================================\n"

command -v unzip >/dev/null 2>&1 || die "unzip is required but not found."

TMP_ROOT="$(mktemp -d -t rt-ai-codex-rtl-uninst-XXXXXX)"
trap 'rm -rf "$TMP_ROOT" 2>/dev/null || true' EXIT

if [[ "$BRANCH" =~ ^v[0-9]+\. ]]; then
    ZIP_URL="https://codeload.github.com/${REPO}/zip/refs/tags/${BRANCH}"
else
    ZIP_URL="https://codeload.github.com/${REPO}/zip/refs/heads/${BRANCH}"
fi
ZIP_PATH="${TMP_ROOT}/source.zip"
EXTRACT_DIR="${TMP_ROOT}/extract"

step "Downloading $ZIP_URL"
curl -fsSL "$ZIP_URL" -o "$ZIP_PATH"
success "Downloaded"

step "Extracting"
mkdir -p "$EXTRACT_DIR"
unzip -q "$ZIP_PATH" -d "$EXTRACT_DIR"
SRC_DIR="$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
[ -n "$SRC_DIR" ] && [ -d "$SRC_DIR" ] || die "Could not locate extracted source directory."

PATCHER="$SRC_DIR/patch.sh"
[ -f "$PATCHER" ] || die "patch.sh not found in the downloaded source."

chmod +x "$PATCHER"

step "Running uninstaller"
"$PATCHER" --uninstall
