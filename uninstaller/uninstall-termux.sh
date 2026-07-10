#!/usr/bin/env bash
# =============================================================================
# Siyarix Termux Uninstaller
#   Removes Siyarix AI Cybersecurity Orchestration Agent from Termux/Android.
#   Supports both Regular and Deep Dive (forensic-grade trace purge) modes.
# =============================================================================
set -euo pipefail

SIYARIX_VERSION="1.0.1"
DRY_RUN=0
UNINSTALL_MODE=""
AUTO_CONFIRM=0
PYTHON=""

banner() {
  echo ""
  echo "   ███████╗██╗██╗   ██╗ █████╗ ██████╗ ██╗██╗  ██╗"
  echo "   ██╔════╝██╚██╗ ██╔╝██╔══██╗██╔══██╗██║╚██╗██╔╝"
  echo "   ███████╗██║╚████╔╝ ███████║██████╔╝██║ ╚███╔╝"
  echo "   ╚════██║██║ ╚██╔╝  ██╔══██║██╔══██╗██║ ██╔██╗"
  echo "   ███████║██║  ██║   ██║  ██║██║  ██║██║██╔╝ ██╗"
  echo "   ╚══════╝╚═╝  ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═╝"
  echo "   AI Cybersecurity Orchestration Agent Uninstaller (Termux)"
  echo ""
}

info()  { echo -e "\033[34m==>\033[0m $*"; }
ok()    { echo -e "\033[32m  ✓\033[0m $*"; }
warn()  { echo -e "\033[33m  !\033[0m $*"; }
err()   { echo -e "\033[31m  ✗\033[0m $*" >&2; }

run() {
  if [ "$DRY_RUN" = "1" ]; then
    info "[DRY-RUN] Would run: $*"
    return 0
  fi
  "$@"
}

# --- Python detection ---
check_python() {
  for cmd in python3 python; do
    if command -v "$cmd" &>/dev/null; then
      local ver
      ver=$("$cmd" --version 2>&1 | grep -oP '\d+\.\d+' | head -1 || "$cmd" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
      local maj="${ver%.*}"
      local min="${ver#*.}"
      if [ "$maj" -ge 3 ] && [ "$min" -ge 11 ]; then
        PYTHON="$cmd"
        return 0
      fi
    fi
  done
  return 1
}

# --- Helper to remove alias/PATH blocks from profile files ---
remove_siyarix_from_profile() {
  local file="$1"
  if [ -f "$file" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      info "[DRY-RUN] Would remove Siyarix PATH/alias references from: $file"
      return 0
    fi
    info "Cleaning up profile: $file"
    local tmp
    tmp=$(mktemp)
    
    # Filter out Siyarix block added by installer
    awk '
    /# Siyarix PATH/ { skip = 2; next }
    /# Siyarix alias/ { skip = 2; next }
    skip > 0 { skip--; next }
    /\.siyarix\/bin/ { next }
    /alias siyarix=/ { next }
    { print }
    ' "$file" > "$tmp"
    
    mv "$tmp" "$file"
    ok "Profile $file cleaned."
  fi
}

# --- Forensic History Cleaner ---
clean_history_file() {
  local hist_file="$1"
  if [ -f "$hist_file" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      info "[DRY-RUN] Would purge Siyarix commands from history: $hist_file"
      return 0
    fi
    
    info "Purging Siyarix commands from history: $hist_file"
    local tmp
    tmp=$(mktemp)
    grep -vi "siyarix" "$hist_file" > "$tmp" || true
    mv "$tmp" "$hist_file"
  fi
}

detect_installations() {
  PIP_DETECTED=0
  CLONE_DETECTED=0

  check_python || true
  if [ -n "$PYTHON" ]; then
    if $PYTHON -m pip show siyarix &>/dev/null; then
      PIP_DETECTED=1
    fi
  fi

  if [ -f "pyproject.toml" ] && [ -d ".git" ]; then
    if grep -q "name = \"siyarix\"" pyproject.toml; then
      CLONE_DETECTED=1
    fi
  fi
}

perform_regular_uninstall() {
  info "Running Regular Uninstallation..."
  local uninstalled=0

  if [ "$PIP_DETECTED" -eq 1 ]; then
    info "Uninstalling Siyarix package..."
    run $PYTHON -m pip uninstall siyarix -y && uninstalled=1
  fi

  if [ "$CLONE_DETECTED" -eq 1 ]; then
    info "Detected local repository clone."
    if [ "$DRY_RUN" = "0" ]; then
      info "Cleaning build artifacts, caches, and virtual environments..."
      rm -rf .venv venv dist build *.egg-info .pytest_cache .mypy_cache .ruff_cache 2>/dev/null || true
      find . -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
      ok "Build caches and virtual environments cleaned from repository."
    fi
  fi

  if [ "$uninstalled" -eq 1 ]; then
    ok "Siyarix package removed successfully."
  else
    warn "No Siyarix package found in Python site-packages."
  fi
}

perform_deep_dive_uninstall() {
  perform_regular_uninstall

  info "Initiating Deep Dive (Forensic-grade trace purge)..."

  # Delete config directory
  local siyarix_dir="$HOME/.siyarix"
  if [ -d "$siyarix_dir" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      info "[DRY-RUN] Would delete config directory: $siyarix_dir"
    else
      info "Deleting configuration, models, logs, and caches at: $siyarix_dir"
      rm -rf "$siyarix_dir"
      ok "Deleted config/data directory."
    fi
  fi

  # Purge OS keyring passwords
  if [ "$DRY_RUN" = "1" ]; then
    info "[DRY-RUN] Would request python to purge Siyarix keyring credentials."
  else
    if [ -n "$PYTHON" ]; then
      info "Checking for OS keyring credentials..."
      if $PYTHON -c "import keyring" &>/dev/null; then
        $PYTHON -c "import keyring; keyring.delete_password('siyarix', 'cred_store_key')" 2>/dev/null || true
        ok "Purged OS keyring entries."
      fi
    fi
  fi

  # Clean up shell profiles (Termux usually uses ~/.bashrc or ~/.zshrc)
  for profile in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    remove_siyarix_from_profile "$profile"
  done

  # Purge shell history (Termux bash/zsh history files)
  for hist in "$HOME/.bash_history" "$HOME/.zsh_history" "$HOME/.sh_history"; do
    clean_history_file "$hist"
  done

  # Purge temporary files
  local termux_tmp="${PREFIX:-/data/data/com.termux/files/usr}/tmp"
  if [ "$DRY_RUN" = "1" ]; then
    info "[DRY-RUN] Would search and delete all files matching 'siyarix' in $termux_tmp and /tmp"
  else
    info "Purging Siyarix temporary files..."
    find /tmp -iname "*siyarix*" -exec rm -rf {} + 2>/dev/null || true
    if [ -d "$termux_tmp" ]; then
      find "$termux_tmp" -iname "*siyarix*" -exec rm -rf {} + 2>/dev/null || true
    fi
    ok "Temporary files cleaned."
  fi

  # Remove pip cache
  if [ -n "$PYTHON" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      info "[DRY-RUN] Would run pip cache purge for Siyarix."
    else
      info "Removing pip cache entries for Siyarix..."
      $PYTHON -m pip cache remove siyarix &>/dev/null || true
      ok "Pip cache cleaned."
    fi
  fi

  ok "Deep dive uninstallation complete. No traces left."
}

main() {
  banner

  # Ensure running in Termux
  if [ ! -d "/data/data/com.termux" ] && [ -z "${TERMUX_VERSION:-}" ]; then
    warn "This script is optimized for Android/Termux environment."
    warn "If you are on standard Linux, please run 'uninstall.sh' instead."
  fi

  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h)
        echo "Usage: bash uninstall-termux.sh [options]"
        echo ""
        echo "Options:"
        echo "  --dry-run       Simulate uninstallation without making changes"
        echo "  --regular       Perform normal package uninstallation without prompting"
        echo "  --deep          Perform deep dive trace purging without prompting"
        echo "  --yes, -y       Auto-confirm all interactive actions"
        echo "  --help, -h      Show this help message"
        exit 0
        ;;
      --dry-run) DRY_RUN=1; info "Dry-run mode enabled"; shift ;;
      --regular) UNINSTALL_MODE="regular"; shift ;;
      --deep)    UNINSTALL_MODE="deep"; shift ;;
      --yes|-y)  AUTO_CONFIRM=1; shift ;;
      *) err "Unknown option: $1"; exit 1 ;;
    esac
  done

  detect_installations

  if [ "$PIP_DETECTED" -eq 0 ] && [ "$CLONE_DETECTED" -eq 0 ]; then
    warn "Siyarix was not detected in Termux site-packages or git clone."
    warn "You can still proceed to purge settings, caches, and traces."
  else
    info "Detected Siyarix installations in Termux:"
    [ "$PIP_DETECTED" -eq 1 ] && ok "  - Installed via pip"
    [ "$CLONE_DETECTED" -eq 1 ] && ok "  - Local Git clone directory"
  fi

  if [ -z "$UNINSTALL_MODE" ]; then
    if [ "$AUTO_CONFIRM" -eq 1 ]; then
      UNINSTALL_MODE="regular"
    else
      echo ""
      echo "Select uninstallation method:"
      echo "  1) Regular [Normal package uninstall]"
      echo "  2) Deep Dive [Forensic cleanup: Purge configs, models, caches, logs, keyring, history]"
      echo -n "Select option (1 or 2): "
      
      local choice=""
      read -r choice
      if [ "$choice" = "2" ]; then
        UNINSTALL_MODE="deep"
      else
        UNINSTALL_MODE="regular"
      fi
    fi
  fi

  if [ "$UNINSTALL_MODE" = "deep" ]; then
    perform_deep_dive_uninstall
  else
    perform_regular_uninstall
  fi

  echo ""
  ok "Done!"
}

main "$@"
