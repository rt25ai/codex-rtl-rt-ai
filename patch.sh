#!/bin/bash
# ============================================================================
# RT-AI ChatGPT Desktop RTL Patcher for macOS
#
# Adds automatic RTL (right-to-left) support to the unified ChatGPT desktop
# app ("Powered by Codex & OWL" - the merged ChatGPT Work + Codex app) on
# macOS. Detects Hebrew/Arabic text and adjusts alignment in real time in
# the composer and streamed responses, while keeping code blocks LTR.
#
# The unified app installs at /Applications/ChatGPT.app (bundle id
# com.openai.codex - it kept Codex's identity and Sparkle updater); older
# Codex builds live at /Applications/Codex.app. Both are supported. The
# native Swift app was renamed "ChatGPT Classic" and is NOT a target of
# this patcher (it has no app.asar).
#
# How it works:
#   1. Copies the app to ~/Applications/ChatGPT-RT-AI.app (original untouched).
#   2. Extracts the app.asar archive.
#   3. Prepends codex-rtl-payload.js to the webview bundles.
#   4. Repacks the archive.
#   5. Best-effort disables the Electron ASAR integrity fuse on the copy
#      (OWL-shell builds have no fuse sentinel; that is fine).
#   6. Re-signs the copied .app with an ad-hoc signature so macOS will run it.
#
# Requirements: Node.js (for npx) and Xcode Command Line Tools (for codesign).
# https://rt-ai.co.il
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PAYLOAD_FILE="$SCRIPT_DIR/codex-rtl-payload.js"

# Default install / source paths. Override via env or flags.
# CHATGPT_SOURCE_APP wins; CODEX_SOURCE_APP is honored for backwards compat.
SOURCE_APP="${CHATGPT_SOURCE_APP:-${CODEX_SOURCE_APP:-}}"
PATCHED_APP="${CHATGPT_PATCHED_APP:-${CODEX_PATCHED_APP:-$HOME/Applications/ChatGPT-RT-AI.app}}"
LEGACY_PATCHED_APPS=("$HOME/Applications/Codex-RT-AI.app")

# Auto-update: a launchd agent re-applies the patch whenever the app updates
# (Sparkle updates the original in place), so the user never re-runs this.
PATCHER_DIR="${CHATGPT_PATCHER_DIR:-${CODEX_PATCHER_DIR:-$HOME/Library/Application Support/ChatGPT-RT-AI-patcher}}"
LEGACY_PATCHER_DIRS=("$HOME/Library/Application Support/Codex-RT-AI-patcher")
AUTOUPDATE_LOG="$PATCHER_DIR/auto-update.log"
LAUNCH_AGENT_LABEL="co.il.rt-ai.chatgpt-rtl.autoupdate"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/$LAUNCH_AGENT_LABEL.plist"
LEGACY_AGENT_LABELS=("co.il.rt-ai.codex-rtl.autoupdate")

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
# Source app discovery
# ---------------------------------------------------------------------------
# A valid source is the Electron/OWL app: it must contain app.asar. This
# also protects against pointing at the native Swift "ChatGPT Classic".
is_electron_app() {
    [ -d "$1" ] && [ -f "$1/Contents/Resources/app.asar" ]
}

resolve_source_app() {
    if [ -n "$SOURCE_APP" ]; then
        is_electron_app "$SOURCE_APP" \
            || die "$SOURCE_APP is not the Electron ChatGPT/Codex app (no Contents/Resources/app.asar)."
        return
    fi

    local candidate
    for candidate in \
        "/Applications/ChatGPT.app" \
        "$HOME/Applications/ChatGPT.app" \
        "/Applications/Codex.app" \
        "$HOME/Applications/Codex.app"
    do
        if is_electron_app "$candidate"; then
            SOURCE_APP="$candidate"
            return
        fi
    done

    die "Could not find the ChatGPT desktop app (checked /Applications and ~/Applications for ChatGPT.app / Codex.app with an app.asar). Install it from https://chatgpt.com/download first, or set CHATGPT_SOURCE_APP."
}

PATCHED_ASAR="$PATCHED_APP/Contents/Resources/app.asar"
MARKER_FILE="$PATCHED_APP/Contents/Resources/rt-ai-chatgpt-rtl-patch.json"

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
quit_patched_app() {
    # Only stop the patched RT-AI copies, never the original app or the CLI.
    local bundle
    for bundle in "ChatGPT-RT-AI" "Codex-RT-AI"; do
        if pgrep -f "$bundle.app" >/dev/null 2>&1; then
            step "Quitting $bundle"
            osascript -e "tell application \"$bundle\" to quit" 2>/dev/null || true
            sleep 2
            pkill -f "$bundle.app/Contents/MacOS" 2>/dev/null || true
            sleep 1
            success "$bundle stopped."
        fi
    done
}

# ---------------------------------------------------------------------------
# Auto-update (launchd agent that re-patches when the app updates)
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

unregister_legacy_autoupdate() {
    # Remove the launchd agent + deployed patcher left behind by the
    # Codex-RT-AI era of this patcher so two agents never race.
    local label plist dir
    for label in "${LEGACY_AGENT_LABELS[@]}"; do
        plist="$HOME/Library/LaunchAgents/$label.plist"
        if [ -f "$plist" ]; then
            launchctl unload "$plist" 2>/dev/null || true
            rm -f "$plist"
            log "Removed legacy auto-update agent: $label"
        fi
    done
    for dir in "${LEGACY_PATCHER_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            rm -rf "$dir" 2>/dev/null || true
            log "Removed legacy patcher dir: $dir"
        fi
    done
}

register_autoupdate() {
    step "Enabling auto-update"
    unregister_legacy_autoupdate
    deploy_patcher
    mkdir -p "$(dirname "$LAUNCH_AGENT_PLIST")"

    # launchd agents run with a bare default PATH (/usr/bin:/bin:/usr/sbin:
    # /sbin) that never contains node/npx (Homebrew installs to
    # /opt/homebrew/bin or /usr/local/bin). Without an explicit PATH the
    # agent could detect updates but never re-patch. Bake in the standard
    # locations plus wherever node lives right now (covers nvm/volta).
    local agent_path="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    local node_bin
    node_bin="$(command -v node 2>/dev/null || true)"
    if [ -n "$node_bin" ]; then
        agent_path="$(dirname "$node_bin"):$agent_path"
    fi

    # Agent runs hourly and at login; the check no-ops fast when the version is
    # unchanged. Sparkle updates the original app silently, so we poll.
    cat > "$LAUNCH_AGENT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LAUNCH_AGENT_LABEL</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$agent_path</string>
    </dict>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$PATCHER_DIR/patch.sh</string>
        <string>--auto-update</string>
    </array>
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
        success "Auto-update enabled. The patch re-applies automatically when ChatGPT updates."
    else
        warn "Could not load the auto-update agent. The patch still works; re-run the installer after a ChatGPT update."
    fi
}

unregister_autoupdate() {
    if [ -f "$LAUNCH_AGENT_PLIST" ]; then
        launchctl unload "$LAUNCH_AGENT_PLIST" 2>/dev/null || true
        rm -f "$LAUNCH_AGENT_PLIST"
    fi
    rm -rf "$PATCHER_DIR" 2>/dev/null || true
    unregister_legacy_autoupdate
}

au_log() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)  $1" >> "$AUTOUPDATE_LOG"; }

auto_update() {
    mkdir -p "$PATCHER_DIR"
    au_log "auto-update check started"

    if [ -z "$SOURCE_APP" ]; then
        local candidate
        for candidate in \
            "/Applications/ChatGPT.app" \
            "$HOME/Applications/ChatGPT.app" \
            "/Applications/Codex.app" \
            "$HOME/Applications/Codex.app"
        do
            if is_electron_app "$candidate"; then SOURCE_APP="$candidate"; break; fi
        done
    fi

    if [ -z "$SOURCE_APP" ] || ! is_electron_app "$SOURCE_APP"; then
        au_log "no ChatGPT/Codex Electron app found; nothing to do"; exit 0
    fi
    if [ ! -d "$PATCHED_APP" ]; then au_log "no patched copy; skip (run --install first)"; exit 0; fi

    # Guarded reads: with set -euo pipefail, sed on a missing marker file
    # would otherwise abort the whole run (and a marker-less half-install
    # could then never self-heal).
    local sv pv legacy_marker
    sv=$(app_version "$SOURCE_APP")
    pv=""
    if [ -f "$MARKER_FILE" ]; then
        pv=$(sed -nE 's/.*"sourceVersion": *"([^"]*)".*/\1/p' "$MARKER_FILE" 2>/dev/null | head -1 || true)
    fi
    # Migrated installs may still carry the old marker name; read it too.
    legacy_marker="$PATCHED_APP/Contents/Resources/rt-ai-codex-rtl-patch.json"
    if [ -z "$pv" ] && [ -f "$legacy_marker" ]; then
        pv=$(sed -nE 's/.*"sourceVersion": *"([^"]*)".*/\1/p' "$legacy_marker" 2>/dev/null | head -1 || true)
    fi
    if [ -n "$pv" ] && [ "$sv" = "$pv" ]; then au_log "already up to date ($sv)"; exit 0; fi

    # Don't interrupt a running session; a later run picks it up.
    if pgrep -f "ChatGPT-RT-AI.app/Contents/MacOS" >/dev/null 2>&1; then
        au_log "update available ($sv) but patched ChatGPT is running; deferring"
        exit 0
    fi

    au_log "updating patch from [$pv] to [$sv]"
    # Re-patch silently, without re-touching the launchd agent we're running
    # under. Running install_patch as an if-condition suppresses errexit
    # inside it, so do NOT trust its exit code alone: independently verify
    # that the payload marker really landed inside the repacked asar (grep -a
    # scans the asar binary directly, no node needed).
    if NO_LAUNCH=1 NO_AUTOUPDATE=1 install_patch >> "$AUTOUPDATE_LOG" 2>&1 \
        && grep -aq "RT-AI CODEX RTL PATCH START" "$PATCHED_ASAR" 2>/dev/null; then
        au_log "re-patched successfully to $sv"
    else
        au_log "re-patch FAILED (payload not verified in $PATCHED_ASAR)"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
install_patch() {
    printf "\n${BOLD}${CYAN}=======================================================${NC}\n"
    printf "${BOLD}${CYAN}     RT-AI ChatGPT Desktop RTL Patcher (macOS)${NC}\n"
    printf "${BOLD}${CYAN}=======================================================${NC}\n\n"

    resolve_source_app
    log "Source app: $SOURCE_APP (v$(app_version "$SOURCE_APP"))"
    [ ! -f "$PAYLOAD_FILE" ] && die "codex-rtl-payload.js not found at $PAYLOAD_FILE. Re-clone the repository."

    check_dependencies
    quit_patched_app

    # Retire the Codex-RT-AI era launchd agent FIRST and unconditionally
    # (even under NO_AUTOUPDATE), so the old agent can never fire mid-install
    # or resurrect the legacy copy after we delete it.
    unregister_legacy_autoupdate

    step "Creating patched copy"
    mkdir -p "$(dirname "$PATCHED_APP")"

    if [ -d "$PATCHED_APP" ]; then
        log "Removing previous patched copy"
        rm -rf "$PATCHED_APP"
    fi

    # Clean up copies made by the older Codex-RT-AI patcher (superseded by
    # this ChatGPT-RT-AI copy).
    local legacy
    for legacy in "${LEGACY_PATCHED_APPS[@]}"; do
        if [ -d "$legacy" ] && [ "$legacy" != "$PATCHED_APP" ]; then
            log "Removing legacy patched copy: $legacy"
            rm -rf "$legacy" 2>/dev/null || warn "Could not remove $legacy"
        fi
    done

    log "Copying $SOURCE_APP -> $PATCHED_APP (this may take a moment)"
    # Explicit '|| die' on every critical step: install_patch is invoked as an
    # if-condition from auto_update, which suppresses errexit inside it.
    cp -R "$SOURCE_APP" "$PATCHED_APP" || die "Copy failed ($SOURCE_APP -> $PATCHED_APP)."
    success "Copied to $PATCHED_APP"

    # Use CFBundleDisplayName so the Dock/Finder show "ChatGPT-RT-AI" without
    # touching CFBundleName (which would break Electron's fuse lookup).
    log "Renaming display name to ChatGPT-RT-AI"
    /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string ChatGPT-RT-AI" \
        "$PATCHED_APP/Contents/Info.plist" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ChatGPT-RT-AI" \
            "$PATCHED_APP/Contents/Info.plist"

    TMP_DIR=$(mktemp -d)
    step "Extracting app.asar"
    asar_cmd extract "$PATCHED_ASAR" "$TMP_DIR/app" || die "asar extract failed."
    success "Extracted"

    step "Injecting RT-AI RTL payload"
    # The app packages its UI under webview/assets/. The exact bundle
    # filenames contain content hashes, so glob for the known prefixes.
    local injected=0
    local skipped=0
    local found_any=0

    local payload_content
    payload_content=$(cat "$PAYLOAD_FILE")

    shopt -s nullglob
    for js_file in \
        "$TMP_DIR"/app/webview/assets/index-*.js \
        "$TMP_DIR"/app/webview/assets/app-main-*.js \
        "$TMP_DIR"/app/webview/assets/composer-*.js
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
        die "No webview bundles found at app/webview/assets/. The app structure may have changed; please report this."
    fi

    [ "$injected" -gt 0 ] && success "Injected RT-AI RTL payload into $injected file(s)."
    [ "$skipped" -gt 0 ] && log "Skipped $skipped already-patched file(s)."

    step "Repacking app.asar"
    asar_cmd pack "$TMP_DIR/app" "$TMP_DIR/app.asar.new" || die "asar pack failed."
    [ -s "$TMP_DIR/app.asar.new" ] || die "asar pack produced no output."
    cp "$TMP_DIR/app.asar.new" "$PATCHED_ASAR" || die "Could not replace $PATCHED_ASAR."
    success "Repacked"

    step "Disabling ASAR integrity fuse on the copy (best-effort)"
    # OWL-shell builds of the unified app ship launchers without the Electron
    # fuse sentinel; @electron/fuses then fails with "Could not find
    # sentinel". That is expected and harmless - such builds do not enforce
    # embedded asar integrity - so never let this step abort the install.
    if fuses_cmd write --app "$PATCHED_APP" EnableEmbeddedAsarIntegrityValidation=off \
        > "$TMP_DIR/fuses.log" 2>&1; then
        success "Fuse disabled"
    else
        warn "No fuse sentinel in this build (OWL shell) - skipping. The repacked asar loads anyway."
    fi

    step "Re-signing the copy with an ad-hoc signature"
    log "Original signature is invalidated by our changes; ad-hoc lets macOS run the copy."
    if ! codesign --force --deep --sign - "$PATCHED_APP" > "$TMP_DIR/codesign.log" 2>&1; then
        while IFS= read -r line; do log "$line"; done < "$TMP_DIR/codesign.log"
        die "codesign failed - the patched app would not launch."
    fi
    success "Re-signed"

    # Patch marker (sourceVersion lets the auto-updater detect new builds)
    cat > "$MARKER_FILE" <<EOF
{
  "name": "rt-ai-chatgpt-rtl-patch",
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
        step "Launching ChatGPT-RT-AI"
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
    quit_patched_app

    step "Removing auto-update agent"
    unregister_autoupdate
    success "Auto-update disabled"

    step "Removing patched app"
    local removed=0
    if [ -d "$PATCHED_APP" ]; then
        rm -rf "$PATCHED_APP"
        success "Removed $PATCHED_APP"
        removed=1
    fi
    local legacy
    for legacy in "${LEGACY_PATCHED_APPS[@]}"; do
        if [ -d "$legacy" ]; then
            rm -rf "$legacy"
            success "Removed legacy copy $legacy"
            removed=1
        fi
    done
    if [ "$removed" -eq 0 ]; then
        warn "No patched app found. Nothing to remove."
    fi
    echo ""
    echo "  The original app was never modified."
    echo ""
}

# ---------------------------------------------------------------------------
# Status
# ---------------------------------------------------------------------------
show_status() {
    echo ""
    printf "${BOLD}RT-AI ChatGPT RTL Patch - Status${NC}\n\n"

    if [ -z "$SOURCE_APP" ]; then
        local candidate
        for candidate in \
            "/Applications/ChatGPT.app" \
            "$HOME/Applications/ChatGPT.app" \
            "/Applications/Codex.app" \
            "$HOME/Applications/Codex.app"
        do
            if is_electron_app "$candidate"; then SOURCE_APP="$candidate"; break; fi
        done
    fi

    if [ -n "$SOURCE_APP" ] && [ -d "$SOURCE_APP" ]; then
        success "Original app: $SOURCE_APP (v$(app_version "$SOURCE_APP"))"
    else
        warn "Original ChatGPT/Codex Electron app: not found"
    fi

    if [ -d "$PATCHED_APP" ]; then
        success "Patched ChatGPT-RT-AI.app: installed (v$(app_version "$PATCHED_APP"))"
        if [ -f "$MARKER_FILE" ] \
            || [ -f "$PATCHED_APP/Contents/Resources/rt-ai-codex-rtl-patch.json" ]; then
            success "RT-AI patch marker present"
        fi
        if command -v npx >/dev/null 2>&1; then
            log "Electron fuse status (no sentinel on OWL builds is expected):"
            fuses_cmd read --app "$PATCHED_APP" 2>/dev/null \
                | grep -E "(EnableEmbeddedAsarIntegrityValidation|Fuse Version)" \
                | while IFS= read -r line; do log "$line"; done \
                || log "No fuse sentinel in this build."
        fi
    else
        log "Patched ChatGPT-RT-AI.app: not installed"
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
    printf "\n${BOLD}RT-AI ChatGPT Desktop RTL Patcher for macOS${NC}\n\n"
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  --install     Install the RTL patch (creates ~/Applications/ChatGPT-RT-AI.app)"
    echo "  --uninstall   Remove the patched app and the auto-update agent"
    echo "  --status      Show current patch status"
    echo "  --auto-update Re-apply the patch if ChatGPT was updated (used by the launchd agent)"
    echo "  --register-autoupdate  (Re)register the auto-update launchd agent only"
    echo "  --help        Show this help"
    echo ""
    echo "Env vars:"
    echo "  CHATGPT_SOURCE_APP   Override source .app path (default: auto-detect"
    echo "                       ChatGPT.app / Codex.app in /Applications and ~/Applications)"
    echo "  CHATGPT_PATCHED_APP  Override patched .app path"
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
