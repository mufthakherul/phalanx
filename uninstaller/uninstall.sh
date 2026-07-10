#!/usr/bin/env bash
# =============================================================================
# Siyarix Universal Uninstaller
#   Removes Siyarix AI Cybersecurity Orchestration Agent from the system.
#   Supports both Regular and Deep Dive (forensic-grade trace purge) modes.
# =============================================================================
set -euo pipefail

SIYARIX_VERSION="1.0.1"
DRY_RUN=0
UNINSTALL_MODE=""
AUTO_CONFIRM=0
PYTHON=""

banner() {
  cat << 'EOF'
   ███████╗██╗██╗   ██╗ █████╗ ██████╗ ██╗██╗  ██╗
   ██╔════╝██╚██╗ ██╔╝██╔══██╗██╔══██╗██║╚██╗██╔╝
   ███████╗██║╚████╔╝ ███████║██████╔╝██║ ╚███╔╝
   ╚════██║██║ ╚██╔╝  ██╔══██║██╔══██╗██║ ██╔██╗
   ███████║██║  ██║   ██║  ██║██║  ██║██║██╔╝ ██╗
   ╚══════╝╚═╝  ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═╝
   AI Cybersecurity Orchestration Agent Uninstaller
EOF
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

# --- Helper to remove blocks from shell profiles ---
remove_siyarix_from_profile() {
  local file="$1"
  if [ -f "$file" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      info "[DRY-RUN] Would remove Siyarix PATH/alias references from: $file"
      return 0
    fi
    info "Cleaning up shell profile: $file"
    local tmp
    tmp=$(mktemp)
    
    # Filter out:
    # 1. Siyarix PATH section (header comment + next export line)
    # 2. Siyarix alias section (header comment + next alias line)
    # 3. Any leftover line containing .siyarix/bin
    awk '
    /# Siyarix PATH/ { skip = 2; next }
    /# Siyarix alias/ { skip = 2; next }
    skip > 0 { skip--; next }
    /\.siyarix\/bin/ { next }
    /alias siyarix=/ { next }
    { print }
    ' "$file" > "$tmp"
    
    mv "$tmp" "$file"
    ok "Shell profile $file cleaned."
  fi
}

# --- Forensic Log Cleaner ---
clean_system_log() {
  local log_file="$1"
  if [ -f "$log_file" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      info "[DRY-RUN] Would purge Siyarix references from log: $log_file"
      return 0
    fi
    
    if [ -w "$log_file" ]; then
      info "Purging Siyarix log lines from $log_file"
      local tmp
      tmp=$(mktemp)
      grep -vi "siyarix" "$log_file" > "$tmp" || true
      cat "$tmp" > "$log_file"
      rm "$tmp"
    elif command -v sudo &>/dev/null; then
      info "Purging Siyarix log lines from $log_file (using sudo)"
      local tmp
      tmp=$(mktemp)
      grep -vi "siyarix" "$log_file" > "$tmp" || true
      sudo dd if="$tmp" of="$log_file" status=none 2>/dev/null || true
      rm "$tmp"
    else
      warn "Log file $log_file is not writable (no write permission or sudo)."
    fi
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

# --- Detection logic ---
detect_installations() {
  PIX_DETECTED=0
  PIP_DETECTED=0
  BREW_DETECTED=0
  APT_DETECTED=0
  DNF_DETECTED=0
  PACMAN_DETECTED=0
  ZYPPER_DETECTED=0
  APK_DETECTED=0
  PKG_DETECTED=0
  PKG_INFO_DETECTED=0
  CLONE_DETECTED=0

  # Check pipx
  if command -v pipx &>/dev/null; then
    if pipx list 2>/dev/null | grep -qi "siyarix"; then
      PIX_DETECTED=1
    fi
  fi

  # Check pip
  check_python || true
  if [ -n "$PYTHON" ]; then
    if $PYTHON -m pip show siyarix &>/dev/null; then
      PIP_DETECTED=1
    fi
  fi

  # Check Homebrew
  if command -v brew &>/dev/null; then
    if brew list siyarix &>/dev/null; then
      BREW_DETECTED=1
    fi
  fi

  # Check apt/dpkg
  if command -v dpkg &>/dev/null; then
    if dpkg -s siyarix &>/dev/null; then
      APT_DETECTED=1
    fi
  fi

  # Check dnf/rpm
  if command -v rpm &>/dev/null; then
    if rpm -q siyarix &>/dev/null; then
      DNF_DETECTED=1
    fi
  fi

  # Check pacman
  if command -v pacman &>/dev/null; then
    if pacman -Qi siyarix &>/dev/null; then
      PACMAN_DETECTED=1
    fi
  fi

  # Check apk (Alpine)
  if command -v apk &>/dev/null; then
    if apk info -e siyarix &>/dev/null; then
      APK_DETECTED=1
    fi
  fi

  # Check zypper
  if command -v zypper &>/dev/null; then
    if zypper search -i siyarix 2>/dev/null | grep -q "^i.*siyarix"; then
      ZYPPER_DETECTED=1
    fi
  fi

  # Check pkg (FreeBSD)
  if command -v pkg &>/dev/null; then
    if pkg info siyarix &>/dev/null; then
      PKG_DETECTED=1
    fi
  fi

  # Check pkg_info / pkgin (OpenBSD / NetBSD)
  if command -v pkg_info &>/dev/null; then
    if pkg_info siyarix &>/dev/null; then
      PKG_INFO_DETECTED=1
    fi
  fi

  # Check local git clone
  if [ -f "pyproject.toml" ] && [ -d ".git" ]; then
    if grep -q "name = \"siyarix\"" pyproject.toml; then
      CLONE_DETECTED=1
    fi
  fi
}

perform_regular_uninstall() {
  info "Running Regular Uninstallation..."
  local uninstalled=0

  if [ "$PIX_DETECTED" -eq 1 ]; then
    info "Uninstalling from pipx..."
    run pipx uninstall siyarix && uninstalled=1
  fi

  if [ "$PIP_DETECTED" -eq 1 ]; then
    info "Uninstalling from pip..."
    run $PYTHON -m pip uninstall siyarix -y && uninstalled=1
  fi

  if [ "$BREW_DETECTED" -eq 1 ]; then
    info "Uninstalling from Homebrew..."
    run brew uninstall siyarix && uninstalled=1
  fi

  if [ "$APT_DETECTED" -eq 1 ]; then
    info "Uninstalling from apt..."
    if [ "$(id -u)" -eq 0 ]; then
      run apt-get remove --purge siyarix -y && uninstalled=1
    elif command -v sudo &>/dev/null; then
      run sudo apt-get remove --purge siyarix -y && uninstalled=1
    else
      warn "Sudo not available. Skipping apt removal."
    fi
  fi

  if [ "$DNF_DETECTED" -eq 1 ]; then
    info "Uninstalling from dnf..."
    if [ "$(id -u)" -eq 0 ]; then
      run dnf remove siyarix -y && uninstalled=1
    elif command -v sudo &>/dev/null; then
      run sudo dnf remove siyarix -y && uninstalled=1
    else
      warn "Sudo not available. Skipping dnf removal."
    fi
  fi

  if [ "$PACMAN_DETECTED" -eq 1 ]; then
    info "Uninstalling from pacman..."
    if [ "$(id -u)" -eq 0 ]; then
      run pacman -Rns siyarix --noconfirm && uninstalled=1
    elif command -v sudo &>/dev/null; then
      run sudo pacman -Rns siyarix --noconfirm && uninstalled=1
    else
      warn "Sudo not available. Skipping pacman removal."
    fi
  fi

  if [ "$ZYPPER_DETECTED" -eq 1 ]; then
    info "Uninstalling from zypper..."
    if [ "$(id -u)" -eq 0 ]; then
      run zypper remove -y siyarix && uninstalled=1
    elif command -v sudo &>/dev/null; then
      run sudo zypper remove -y siyarix && uninstalled=1
    else
      warn "Sudo not available. Skipping zypper removal."
    fi
  fi

  if [ "$APK_DETECTED" -eq 1 ]; then
    info "Uninstalling from apk..."
    if [ "$(id -u)" -eq 0 ]; then
      run apk del siyarix && uninstalled=1
    elif command -v sudo &>/dev/null; then
      run sudo apk del siyarix && uninstalled=1
    else
      warn "Sudo not available. Skipping apk removal."
    fi
  fi

  if [ "$PKG_DETECTED" -eq 1 ]; then
    info "Uninstalling from pkg (FreeBSD)..."
    if [ "$(id -u)" -eq 0 ]; then
      run pkg delete -y siyarix && uninstalled=1
    elif command -v sudo &>/dev/null; then
      run sudo pkg delete -y siyarix && uninstalled=1
    fi
  fi

  if [ "$PKG_INFO_DETECTED" -eq 1 ]; then
    info "Uninstalling from pkg_delete/pkgin..."
    if [ "$(id -u)" -eq 0 ]; then
      if command -v pkgin &>/dev/null; then
        run pkgin remove -y siyarix && uninstalled=1
      else
        run pkg_delete siyarix && uninstalled=1
      fi
    elif command -v sudo &>/dev/null; then
      if command -v pkgin &>/dev/null; then
        run sudo pkgin remove -y siyarix && uninstalled=1
      else
        run sudo pkg_delete siyarix && uninstalled=1
      fi
    fi
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
    ok "Siyarix packages removed successfully."
  else
    warn "No active package-based installation found. Proceeding."
  fi
}

perform_deep_dive_uninstall() {
  # Step 1: Normal Package removal
  perform_regular_uninstall

  info "Initiating Deep Dive (Forensic-grade trace purge)..."

  # Step 2: Delete Configuration / Caches / Logs / Data Directory
  local siyarix_dir=""
  local env_config="${SIYARIX_CONFIG_DIR:-${SIYARIX_HOME:-${SIYARIX_CONFIG:-}}}"
  if [ -n "$env_config" ]; then
    siyarix_dir=$(eval echo "$env_config")
  else
    siyarix_dir="$HOME/.siyarix"
  fi

  if [ -d "$siyarix_dir" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      info "[DRY-RUN] Would delete config and data directory: $siyarix_dir"
    else
      info "Deleting configuration, models, logs, and caches at: $siyarix_dir"
      rm -rf "$siyarix_dir"
      ok "Deleted config/data directory."
    fi
  fi

  # Step 3: Remove Keyring Credentials
  if [ "$DRY_RUN" = "1" ]; then
    info "[DRY-RUN] Would request python to purge Siyarix OS keyring credentials."
  else
    if [ -n "$PYTHON" ]; then
      info "Checking for OS keyring credentials..."
      if $PYTHON -c "import keyring" &>/dev/null; then
        $PYTHON -c "import keyring; keyring.delete_password('siyarix', 'cred_store_key')" 2>/dev/null || true
        ok "Purged OS keyring entries."
      fi
    fi
  fi

  # Step 4: Clean up Shell PATH modifications and aliases
  for profile in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.kshrc"; do
    remove_siyarix_from_profile "$profile"
  done

  # Step 5: Purge Shell History (Forensic Trace Cleanup)
  for hist in "$HOME/.bash_history" "$HOME/.zsh_history" "$HOME/.sh_history" "$HOME/.history" "$HOME/.local/share/fish/fish_history"; do
    clean_history_file "$hist"
  done

  # Step 6: Purge System Log references (Forensic Trace Cleanup)
  for log in "/var/log/dpkg.log" "/var/log/apt/history.log" "/var/log/apt/term.log" "/var/log/pacman.log" "/var/log/dnf.log" "/var/log/yum.log"; do
    clean_system_log "$log"
  done

  # Homebrew log directories
  local brew_log_dir="$HOME/Library/Logs/Homebrew/siyarix"
  if [ -d "$brew_log_dir" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      info "[DRY-RUN] Would remove Homebrew log directory: $brew_log_dir"
    else
      info "Removing Homebrew log directory..."
      rm -rf "$brew_log_dir"
    fi
  fi

  # Step 7: Clear Temporary Files
  if [ "$DRY_RUN" = "1" ]; then
    info "[DRY-RUN] Would search and delete all files matching 'siyarix' in /tmp and /var/tmp"
  else
    info "Purging Siyarix temporary files from /tmp and /var/tmp..."
    find /tmp -iname "*siyarix*" -exec rm -rf {} + 2>/dev/null || true
    find /var/tmp -iname "*siyarix*" -exec rm -rf {} + 2>/dev/null || true
    ok "Temporary files cleaned."
  fi

  # Step 8: Remove pip caches
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

# --- Main execution flow ---
main() {
  banner

  while [ $# -gt 0 ]; do
    case "$1" in
      --help|-h)
        echo "Usage: bash uninstall.sh [options]"
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
      *) err "Unknown option: $1. Use --help for usage."; exit 1 ;;
    esac
  done

  detect_installations

  if [ "$PIX_DETECTED" -eq 0 ] && [ "$PIP_DETECTED" -eq 0 ] && [ "$BREW_DETECTED" -eq 0 ] && \
     [ "$APT_DETECTED" -eq 0 ] && [ "$DNF_DETECTED" -eq 0 ] && [ "$PACMAN_DETECTED" -eq 0 ] && \
     [ "$ZYPPER_DETECTED" -eq 0 ] && [ "$APK_DETECTED" -eq 0 ] && [ "$PKG_DETECTED" -eq 0 ] && \
     [ "$PKG_INFO_DETECTED" -eq 0 ] && [ "$CLONE_DETECTED" -eq 0 ]; then
    warn "No installation of Siyarix was auto-detected on this system."
    warn "However, you can still proceed to purge configurations or traces."
  else
    info "Detected Siyarix installations:"
    [ "$PIX_DETECTED" -eq 1 ] && ok "  - Installed via pipx"
    [ "$PIP_DETECTED" -eq 1 ] && ok "  - Installed via pip (Python: $($PYTHON --version 2>&1))"
    [ "$BREW_DETECTED" -eq 1 ] && ok "  - Installed via Homebrew"
    [ "$APT_DETECTED" -eq 1 ] && ok "  - Installed via apt package manager"
    [ "$DNF_DETECTED" -eq 1 ] && ok "  - Installed via dnf package manager"
    [ "$PACMAN_DETECTED" -eq 1 ] && ok "  - Installed via pacman package manager"
    [ "$ZYPPER_DETECTED" -eq 1 ] && ok "  - Installed via zypper package manager"
    [ "$APK_DETECTED" -eq 1 ] && ok "  - Installed via apk package manager"
    [ "$PKG_DETECTED" -eq 1 ] && ok "  - Installed via pkg (FreeBSD)"
    [ "$PKG_INFO_DETECTED" -eq 1 ] && ok "  - Installed via pkg_add/pkgin (OpenBSD/NetBSD)"
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
