#!/bin/bash
# ============================================================================
# RT-AI Codex Desktop RTL Patcher for macOS
#
# Adds automatic RTL (right-to-left) support to OpenAI Codex Desktop on macOS.
# Detects Hebrew/Arabic text and adjusts alignment in real time in the
# composer and streamed responses, while keeping code blocks LTR.
#
# Modeled after the standard pattern for patching Electron apps on macOS:
# extract app.asar, inject JS, repack, disable integrity fuse, re-sign.
#
# How it works:
#   1. Copies Codex Desktop (Codex.app, or ChatGPT.app on 26.x) to
#      ~/Applications/Codex-RT-AI.app (original untouched).
#   2. Extracts the app.asar archive.
#   3. Prepends codex-rtl-payload.js to the Codex webview bundles.
#   4. Repacks the archive.
#   5. Disables the Electron ASAR integrity fuse on the copy.
#   6. Re-signs the copied .app with an ad-hoc signature so macOS will run it.
#
# Requirements: Node.js (for npx) and Xcode Command Line Tools (for codesign).
# https://rt-ai.co.il
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PAYLOAD_FILE="$SCRIPT_DIR/codex-rtl-payload.js"

# Read an app bundle's identifier ("" if unavailable).
bundle_id() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
        "$1/Contents/Info.plist" 2>/dev/null || echo ""
}

# Locate Codex Desktop.
#
# Codex Desktop 26.x ships as ChatGPT.app instead of Codex.app. The bundle
# identifier stayed com.openai.codex, so match on that rather than the
# filename: the consumer ChatGPT desktop app is a different product
# (com.openai.chat) that can occupy /Applications/ChatGPT.app, and patching it
# would be wrong.
detect_source_app() {
    local candidate
    for candidate in /Applications/Codex.app /Applications/ChatGPT.app; do
        if [ -d "$candidate" ] && [ "$(bundle_id "$candidate")" = "com.openai.codex" ]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    # Nothing found: keep the historical path so error messages stay familiar.
    printf '%s' "/Applications/Codex.app"
}

# Default install / source paths. Override via env or flags.
SOURCE_APP="${CODEX_SOURCE_APP:-$(detect_source_app)}"
PATCHED_APP="${CODEX_PATCHED_APP:-$HOME/Applications/Codex-RT-AI.app}"
PATCHED_ASAR="$PATCHED_APP/Contents/Resources/app.asar"
MARKER_FILE="$PATCHED_APP/Contents/Resources/rt-ai-codex-rtl-patch.json"

# Auto-update: a launchd agent re-applies the patch whenever Codex updates,
# so the user never has to re-run the installer.
PATCHER_DIR="${CODEX_PATCHER_DIR:-$HOME/Library/Application Support/Codex-RT-AI-patcher}"
AUTOUPDATE_LOG="$PATCHER_DIR/auto-update.log"
LAUNCH_AGENT_LABEL="co.il.rt-ai.codex-rtl.autoupdate"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/$LAUNCH_AGENT_LABEL.plist"

TMP_DIR=""

# Read an app bundle's short version string ("unknown" if unavailable).
app_version() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
        "$1/Contents/Info.plist" 2>/dev/null || echo "unknown"
}

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()     { printf "  ${CYAN}[*]${NC} %s\n" "$1"; }
success() { printf "  ${GREEN}[+]${NC} %s\n" "$1"; }
warn()    { printf "  ${YELLOW}[!]${NC} %s\n" "$1"; }
err()     { printf "  ${RED}[X]${NC} %s\n" "$1"; }
step()    { printf "\n${BOLD}${CYAN}==> %s${NC}\n" "$1"; }
die()     { err "$1"; exit 1; }

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
cleanup() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Tool helpers
# ---------------------------------------------------------------------------
asar_cmd() {
    if command -v asar >/dev/null 2>&1; then
        asar "$@"
    elif command -v npx >/dev/null 2>&1; then
        npx --yes @electron/asar "$@"
    else
        die "Bug: asar_cmd called without asar or npx available."
    fi
}

fuses_cmd() {
    if command -v npx >/dev/null 2>&1; then
        npx --yes @electron/fuses "$@"
    else
        die "Bug: fuses_cmd called without npx available."
    fi
}

check_dependencies() {
    local missing=()

    if ! command -v npx >/dev/null 2>&1 && ! command -v asar >/dev/null 2>&1; then
        missing+=("Node.js (provides npx) or @electron/asar")
    fi

    if ! command -v npx >/dev/null 2>&1; then
        missing+=("Node.js (provides npx, needed for @electron/fuses)")
    fi

    if ! command -v codesign >/dev/null 2>&1; then
        missing+=("Xcode Command Line Tools (provides codesign)")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        err "Missing required dependencies:"
        for dep in "${missing[@]}"; do
            printf "    - %s\n" "$dep"
        done
        echo ""
        echo "  Install Node.js: https://nodejs.org/ or 'brew install node'"
        echo "  Install Xcode CLI tools: xcode-select --install"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Process management
# ---------------------------------------------------------------------------
quit_patched_codex() {
    # Only stop the patched RT-AI copy, never the original Codex or Codex CLI.
    if pgrep -f "Codex-RT-AI.app" >/dev/null 2>&1; then
        step "Quitting Codex-RT-AI"
        osascript -e 'tell application "Codex-RT-AI" to quit' 2>/dev/null || true
        sleep 2
        pkill -f "Codex-RT-AI.app/Contents/MacOS" 2>/dev/null || true
        sleep 1
        success "Codex-RT-AI stopped."
    fi
}

# ---------------------------------------------------------------------------
# Auto-update (launchd agent that re-patches when Codex updates)
# ---------------------------------------------------------------------------
deploy_patcher() {
    # Copy this script + payload to a stable location so the launchd agent has
    # something persistent to run (the online installer runs from a temp dir).
    mkdir -p "$PATCHER_DIR"
    local self="$SCRIPT_DIR/$(basename "$0")"
    if [ -f "$self" ] && [ "$self" != "$PATCHER_DIR/patch.sh" ]; then
        cp "$self" "$PATCHER_DIR/patch.sh" 2>/dev/null || true
        chmod +x "$PATCHER_DIR/patch.sh" 2>/dev/null || true
    fi
    if [ -f "$PAYLOAD_FILE" ] && [ "$PAYLOAD_FILE" != "$PATCHER_DIR/codex-rtl-payload.js" ]; then
        cp "$PAYLOAD_FILE" "$PATCHER_DIR/codex-rtl-payload.js" 2>/dev/null || true
    fi
}

register_autoupdate() {
    step "Enabling auto-update"
    deploy_patcher
    mkdir -p "$(dirname "$LAUNCH_AGENT_PLIST")"

    # Agent runs hourly and at login; the check no-ops fast when the version is
    # unchanged. macOS has no Store-update event, so we poll on an interval.
    cat > "$LAUNCH_AGENT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LAUNCH_AGENT_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$PATCHER_DIR/patch.sh</string>
        <string>--auto-update</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <!-- Carry the resolved source app so an explicit CODEX_SOURCE_APP
             override survives auto-updates. -->
        <key>CODEX_SOURCE_APP</key>
        <string>$SOURCE_APP</string>
        <!-- launchd agents get a minimal PATH, so a node installed via nvm or
             Homebrew is invisible and the re-patch dies in check_dependencies. -->
        <key>PATH</key>
        <string>$(dirname "$(command -v node)"):/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>3600</integer>
    <key>StandardOutPath</key>
    <string>$AUTOUPDATE_LOG</string>
    <key>StandardErrorPath</key>
    <string>$AUTOUPDATE_LOG</string>
</dict>
</plist>
EOF

    launchctl unload "$LAUNCH_AGENT_PLIST" 2>/dev/null || true
    if launchctl load "$LAUNCH_AGENT_PLIST" 2>/dev/null; then
        success "Auto-update enabled. The patch re-applies automatically when Codex updates."
    else
        warn "Could not load the auto-update agent. The patch still works; re-run the installer after a Codex update."
    fi
}

unregister_autoupdate() {
    if [ -f "$LAUNCH_AGENT_PLIST" ]; then
        launchctl unload "$LAUNCH_AGENT_PLIST" 2>/dev/null || true
        rm -f "$LAUNCH_AGENT_PLIST"
    fi
    rm -rf "$PATCHER_DIR" 2>/dev/null || true
}

au_log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)  $1" >> "$AUTOUPDATE_LOG"; }

auto_update() {
    mkdir -p "$PATCHER_DIR"
    au_log "auto-update check started"

    if [ ! -d "$SOURCE_APP" ]; then au_log "no Codex Desktop at $SOURCE_APP; nothing to do"; exit 0; fi
    if [ ! -d "$PATCHED_APP" ]; then au_log "no patched copy; skip (run --install first)"; exit 0; fi

    local sv pv
    sv=$(app_version "$SOURCE_APP")
    pv=$(sed -nE 's/.*"sourceVersion": *"([^"]*)".*/\1/p' "$MARKER_FILE" 2>/dev/null | head -1)
    if [ -n "$pv" ] && [ "$sv" = "$pv" ]; then au_log "already up to date ($sv)"; exit 0; fi

    # Don't interrupt a running session; a later run picks it up.
    if pgrep -f "Codex-RT-AI.app/Contents/MacOS" >/dev/null 2>&1; then
        au_log "update available ($sv) but patched Codex is running; deferring"
        exit 0
    fi

    au_log "updating patch from [$pv] to [$sv]"
    # Re-patch silently, without re-touching the launchd agent we're running under.
    if NO_LAUNCH=1 NO_AUTOUPDATE=1 install_patch >> "$AUTOUPDATE_LOG" 2>&1; then
        au_log "re-patched successfully to $sv"
    else
        au_log "re-patch FAILED"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
install_patch() {
    printf "\n${BOLD}${CYAN}=======================================================${NC}\n"
    printf "${BOLD}${CYAN}     RT-AI Codex Desktop RTL Patcher (macOS)${NC}\n"
    printf "${BOLD}${CYAN}=======================================================${NC}\n\n"

    [ ! -d "$SOURCE_APP" ] && die "Codex Desktop not found (looked for Codex.app and ChatGPT.app in /Applications). Install it first, or set CODEX_SOURCE_APP."
    [ ! -f "$PAYLOAD_FILE" ] && die "codex-rtl-payload.js not found at $PAYLOAD_FILE. Re-clone the repository."

    check_dependencies
    quit_patched_codex

    step "Creating patched copy"
    mkdir -p "$(dirname "$PATCHED_APP")"

    if [ -d "$PATCHED_APP" ]; then
        log "Removing previous patched copy"
        rm -rf "$PATCHED_APP"
    fi

    log "Copying $SOURCE_APP -> $PATCHED_APP (this may take a moment)"
    cp -R "$SOURCE_APP" "$PATCHED_APP"
    success "Copied to $PATCHED_APP"

    # Use CFBundleDisplayName so the Dock/Finder show "Codex-RT-AI" without
    # touching CFBundleName (which would break Electron's fuse lookup).
    log "Renaming display name to Codex-RT-AI"
    /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string Codex-RT-AI" \
        "$PATCHED_APP/Contents/Info.plist" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Codex-RT-AI" \
            "$PATCHED_APP/Contents/Info.plist"

    TMP_DIR=$(mktemp -d)
    step "Extracting app.asar"
    asar_cmd extract "$PATCHED_ASAR" "$TMP_DIR/app"
    success "Extracted"

    step "Injecting RT-AI RTL payload"
    # Codex packages its UI under webview/assets/. The exact bundle filenames
    # contain content hashes, so glob for the three known prefixes.
    local injected=0
    local skipped=0
    local found_any=0

    local payload_content
    payload_content=$(cat "$PAYLOAD_FILE")

    shopt -s nullglob
    for js_file in \
        "$TMP_DIR"/app/webview/assets/index-*.js \
        "$TMP_DIR"/app/webview/assets/app-main-*.js \
        "$TMP_DIR"/app/webview/assets/composer-*.js \
        "$TMP_DIR"/app/webview/assets/composer-atoms-*.js
    do
        [ -f "$js_file" ] || continue
        found_any=1

        if grep -q "RT-AI CODEX RTL PATCH START" "$js_file" 2>/dev/null; then
            skipped=$((skipped + 1))
            continue
        fi

        printf "%s\n" "$payload_content" > "$TMP_DIR/merged.js"
        cat "$js_file" >> "$TMP_DIR/merged.js"
        mv "$TMP_DIR/merged.js" "$js_file"
        injected=$((injected + 1))
        log "Injected into $(basename "$js_file")"
    done
    shopt -u nullglob

    if [ "$found_any" -eq 0 ]; then
        die "No Codex webview bundles found at app/webview/assets/. The app structure may have changed; please report this."
    fi

    [ "$injected" -gt 0 ] && success "Injected RT-AI RTL payload into $injected file(s)."
    [ "$skipped" -gt 0 ] && log "Skipped $skipped already-patched file(s)."

    step "Repacking app.asar"
    asar_cmd pack "$TMP_DIR/app" "$TMP_DIR/app.asar.new"
    cp "$TMP_DIR/app.asar.new" "$PATCHED_ASAR"
    success "Repacked"

    step "Disabling ASAR integrity fuse on the copy"
    # @electron/fuses locates the fuse wire via
    # Contents/Frameworks/Electron Framework.framework/Electron Framework.
    # Codex 26.x renamed that framework to "Codex Framework.framework", so the
    # call fails with ENOENT and set -e aborts the install. That build already
    # ships EnableEmbeddedAsarIntegrityValidation=Disabled, so skip the step
    # instead of shimming the path. If a future build restores the stock
    # framework name, this runs again unchanged.
    if [ -f "$PATCHED_APP/Contents/Frameworks/Electron Framework.framework/Electron Framework" ]; then
        log "Required after modifying app.asar; the original .app is not touched."
        fuses_cmd write --app "$PATCHED_APP" EnableEmbeddedAsarIntegrityValidation=off \
            2>&1 | while IFS= read -r line; do log "$line"; done
        success "Fuse disabled"
    else
        log "Stock Electron Framework not present; this build ships the ASAR integrity fuse off. Skipping."
    fi

    step "Re-signing the copy with an ad-hoc signature"
    log "Original signature is invalidated by our changes; ad-hoc lets macOS run the copy."
    codesign --force --deep --sign - "$PATCHED_APP" 2>&1 \
        | while IFS= read -r line; do log "$line"; done
    success "Re-signed"

    # Patch marker (sourceVersion lets the auto-updater detect new Codex builds)
    cat > "$MARKER_FILE" <<EOF
{
  "name": "rt-ai-codex-rtl-patch",
  "publisher": "RT-AI",
  "site": "https://rt-ai.co.il",
  "platform": "macos",
  "sourceAppDir": "$SOURCE_APP",
  "sourceVersion": "$(app_version "$SOURCE_APP")",
  "installedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

    rm -rf "$TMP_DIR" 2>/dev/null || true
    TMP_DIR=""

    if [ -z "${NO_AUTOUPDATE:-}" ]; then
        register_autoupdate || true
    fi

    if [ -n "${NO_LAUNCH:-}" ]; then
        log "Skipping launch (NO_LAUNCH set)."
    else
        step "Launching Codex-RT-AI"
        open "$PATCHED_APP"
    fi

    printf "\n${BOLD}${GREEN}=======================================================${NC}\n"
    printf "${BOLD}${GREEN}     PATCH INSTALLED${NC}\n"
    printf "${BOLD}${GREEN}=======================================================${NC}\n\n"
    printf "  Patched app:  ${BOLD}%s${NC}\n" "$PATCHED_APP"
    printf "  Original app: ${BOLD}%s${NC} (untouched)\n\n" "$SOURCE_APP"
    echo "  To remove the patch:    $0 --uninstall"
    echo "  To show status:         $0 --status"
    echo ""
}

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------
uninstall_patch() {
    if [ ! -d "$PATCHED_APP" ]; then
        warn "No patched app found at $PATCHED_APP. Nothing to remove."
        exit 0
    fi

    quit_patched_codex

    step "Removing auto-update agent"
    unregister_autoupdate
    success "Auto-update disabled"

    step "Removing patched app"
    rm -rf "$PATCHED_APP"
    success "Removed $PATCHED_APP"
    echo ""
    echo "  The original app at $SOURCE_APP was never modified."
    echo ""
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------
show_status() {
    echo ""
    printf "${BOLD}RT-AI Codex RTL Patch - Status${NC}\n\n"

    if [ -d "$SOURCE_APP" ]; then
        local version
        version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
            "$SOURCE_APP/Contents/Info.plist" 2>/dev/null || echo "unknown")
        success "Original Codex Desktop at $SOURCE_APP: installed (v$version)"
    else
        warn "Original Codex Desktop: not found at $SOURCE_APP"
    fi

    if [ -d "$PATCHED_APP" ]; then
        local pv
        pv=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
            "$PATCHED_APP/Contents/Info.plist" 2>/dev/null || echo "unknown")
        success "Patched Codex-RT-AI.app: installed (v$pv)"
        if [ -f "$PATCHED_APP/Contents/Resources/rt-ai-codex-rtl-patch.json" ]; then
            success "RT-AI patch marker present"
        fi
        if command -v npx >/dev/null 2>&1; then
            log "Electron fuse status:"
            fuses_cmd read --app "$PATCHED_APP" 2>/dev/null | grep -E "(EnableEmbeddedAsarIntegrityValidation|Fuse Version)" \
                | while IFS= read -r line; do log "$line"; done
        fi
    else
        log "Patched Codex-RT-AI.app: not installed"
    fi

    if [ -f "$LAUNCH_AGENT_PLIST" ]; then
        success "Auto-update: enabled (launchd agent $LAUNCH_AGENT_LABEL)"
    else
        log "Auto-update: not enabled. Re-run --install to enable it."
    fi
    echo ""
}

# ---------------------------------------------------------------------------
# Usage / dispatch
# ---------------------------------------------------------------------------
usage() {
    printf "\n${BOLD}RT-AI Codex Desktop RTL Patcher for macOS${NC}\n\n"
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  --install     Install the RTL patch (creates ~/Applications/Codex-RT-AI.app)"
    echo "  --uninstall   Remove the patched app and the auto-update agent"
    echo "  --status      Show current patch status"
    echo "  --auto-update Re-apply the patch if Codex was updated (used by the launchd agent)"
    echo "  --help        Show this help"
    echo ""
    echo "Env vars:"
    echo "  CODEX_SOURCE_APP  Override source .app path (default: auto-detected Codex.app or ChatGPT.app)"
    echo "  CODEX_PATCHED_APP Override patched .app path"
    echo ""
}

case "${1:---install}" in
    --install)             install_patch ;;
    --uninstall)           uninstall_patch ;;
    --status)              show_status ;;
    --auto-update)         auto_update ;;
    --register-autoupdate) register_autoupdate ;;
    --help|-h)             usage ;;
    *)                     err "Unknown option: $1"; usage; exit 1 ;;
esac
