#!/usr/bin/env bash

# ==============================================================================
#  devenv-setup.sh — Linux Dev Environment Bootstrap
#  Supports: Debian/Ubuntu (apt) | Fedora/RHEL (dnf)
#  Idempotent. Interactive. Single-file.
# ==============================================================================

set -uo pipefail

# ==============================================================================
# COLORS & LOGGING
# ==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

log_info()    { echo -e "  ${BLUE}→${RESET}  $*"; }
log_ok()      { echo -e "  ${GREEN}✔${RESET}  $*"; }
log_skip()    { echo -e "  ${YELLOW}✖${RESET}  Skipping: ${DIM}$*${RESET}"; }
log_warn()    { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
log_error()   { echo -e "  ${RED}✘${RESET}  $*" >&2; }
log_section() {
    echo ""
    echo -e "  ${BOLD}${CYAN}┌─────────────────────────────────────────┐${RESET}"
    printf   "  ${BOLD}${CYAN}│${RESET}  %-41s${BOLD}${CYAN}│${RESET}\n" "$*"
    echo -e  "  ${BOLD}${CYAN}└─────────────────────────────────────────┘${RESET}"
}

# Summary tracking
INSTALLED=()
SKIPPED=()

# ==============================================================================
# HELPERS
# ==============================================================================
ask() {
    local prompt="$1"
    local response
    echo -ne "\n  ${BOLD}${YELLOW}?${RESET}  $prompt ${DIM}[y/N]${RESET}: "
    read -r response
    [[ "$response" =~ ^[Yy]$ ]]
}

is_cmd() { command -v "$1" &>/dev/null; }

pkg_install() {
    $PKG_INSTALL "$@" 2>&1 | grep -v "^$" | tail -3 || true
}

require_sudo() {
    if ! sudo -n true 2>/dev/null; then
        log_info "Sudo access required. You may be prompted for your password."
    fi
}

# ==============================================================================
# OS DETECTION
# ==============================================================================
detect_os() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "/etc/os-release not found. Cannot detect OS."
        exit 1
    fi

    # shellcheck source=/dev/null
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_ID_LIKE="${ID_LIKE:-}"
    OS_PRETTY="${PRETTY_NAME:-$OS_ID}"

    case "$OS_ID" in
        debian|ubuntu|linuxmint|pop|kali|raspbian)
            DISTRO_FAMILY="debian"
            ;;
        fedora)
            DISTRO_FAMILY="fedora"
            ;;
        rhel|centos|rocky|almalinux)
            DISTRO_FAMILY="fedora"
            ;;
        *)
            if [[ "$OS_ID_LIKE" == *"debian"* ]]; then
                DISTRO_FAMILY="debian"
            elif [[ "$OS_ID_LIKE" == *"fedora"* || "$OS_ID_LIKE" == *"rhel"* ]]; then
                DISTRO_FAMILY="fedora"
            else
                log_error "Unsupported distro: $OS_PRETTY"
                log_error "Supported families: Debian/Ubuntu, Fedora/RHEL"
                exit 1
            fi
            ;;
    esac

    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        PKG_INSTALL="sudo apt-get install -y"
        PKG_UPDATE="sudo apt-get update -y"
    else
        PKG_INSTALL="sudo dnf install -y"
        PKG_UPDATE="sudo dnf check-update"
    fi

    log_ok "OS: ${BOLD}${OS_PRETTY}${RESET} (family: ${DISTRO_FAMILY})"
}

# ==============================================================================
# 1. BASE PACKAGES
# ==============================================================================
install_base() {
    log_section "Base Packages"
    require_sudo

    log_info "Updating package database..."
    eval "$PKG_UPDATE" &>/dev/null || true

    local packages=(git curl wget unzip zsh tmux fzf)
    for pkg in "${packages[@]}"; do
        if is_cmd "$pkg"; then
            log_ok "$pkg — already present"
        else
            log_info "Installing $pkg..."
            pkg_install "$pkg" \
                && log_ok "$pkg installed" \
                || log_warn "Failed to install $pkg"
        fi
    done

    INSTALLED+=("base-packages (git curl wget unzip zsh tmux fzf)")
}

# ==============================================================================
# 2. ZSH SETUP
# ==============================================================================
setup_zsh() {
    log_section "ZSH Configuration"

    # Directory structure
    mkdir -p "$HOME/.zsh/tools"
    log_info "Writing ~/.zshrc ..."

    cat > "$HOME/.zshrc" << 'ZSHRC_EOF'
# === PATH SAFETY ===
typeset -U path
path=($HOME/.local/bin $path)

export PATH=$PATH:/sbin:/usr/sbin
export LS_COLORS="di=34:ln=36:so=35:pi=33:ex=32:bd=33:cd=33:su=31:sg=31:tw=30:ow=30"

# === BASIC ENV ===
export EDITOR='code'
export PAGER='less'
export LANG=en_IN.UTF-8

# === LOAD MODULES ===
ZSH_CONFIG_DIR="$HOME/.zsh"

source "$ZSH_CONFIG_DIR/core.zsh"
source "$ZSH_CONFIG_DIR/aliases.zsh"
source "$ZSH_CONFIG_DIR/functions.zsh"
source "$ZSH_CONFIG_DIR/plugins.zsh"

# === LOAD OPTIONAL TOOLS ===
for file in "$ZSH_CONFIG_DIR/tools/"*.zsh; do
  [ -r "$file" ] && source "$file"
done
ZSHRC_EOF

    log_info "Writing ~/.zsh/core.zsh ..."
    cat > "$HOME/.zsh/core.zsh" << 'CORE_EOF'
# === HISTORY ===
setopt histignorealldups sharehistory
setopt histignorespace
setopt inc_append_history

HISTSIZE=5000
SAVEHIST=5000
HISTFILE=~/.zsh_history

# === KEYBINDINGS ===
bindkey -e

# === COMPLETION ===
autoload -Uz compinit
compinit -C

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
CORE_EOF

    log_info "Writing ~/.zsh/aliases.zsh ..."
    cat > "$HOME/.zsh/aliases.zsh" << 'ALIASES_EOF'
# === BASIC ===
alias cls='clear'
alias c='clear'
alias q='exit'

alias free='free -h'
alias df='df -h'

# === NAVIGATION ===
alias ..='cd ..'
alias ...='cd ../..'

alias cat='bat --style=plain --paging=never'
alias catp='bat --style=numbers --color=always'

# === MODERN LS (lsd themed) ===
if command -v lsd &> /dev/null; then
  alias ls='lsd --group-dirs=first --icon=auto --color=always'
  alias ll='lsd -lh --group-dirs=first --icon=auto --color=always'
  alias la='lsd -lah --group-dirs=first --icon=auto --color=always'
  alias l='lsd -lah --git --group-dirs=first --icon=auto --color=always'
  alias lt='lsd --tree --depth=2 --icon=auto'
  alias lT='lsd --tree --icon=auto'
  alias lsize='lsd -lh --sizesort'
  alias ltime='lsd -lh --timesort'
else
  alias ls='ls --color=auto'
  alias ll='ls -lh'
  alias la='ls -lah'
fi

# === GIT ===
alias gs='git status'
alias gp='git push'
alias gc='git commit -m'
ALIASES_EOF

    log_info "Writing ~/.zsh/functions.zsh ..."
    cat > "$HOME/.zsh/functions.zsh" << 'FUNCTIONS_EOF'
# Create and enter directory
mkcd() {
  mkdir -p "$1" && cd "$1"
}

# Reload config
reload() {
  source ~/.zshrc
}

# Extract files
extract() {
  case "$1" in
    *.tar.gz)  tar xzf "$1" ;;
    *.tar.bz2) tar xjf "$1" ;;
    *.tar.xz)  tar xJf "$1" ;;
    *.zip)     unzip "$1" ;;
    *.7z)      7z x "$1" ;;
    *.gz)      gunzip "$1" ;;
    *.rar)     unrar x "$1" ;;
    *)         echo "Unsupported format: $1" ;;
  esac
}

# Quick HTTP server
serve() {
  local port="${1:-8000}"
  python3 -m http.server "$port"
}

# Git log pretty
glog() {
  git log --oneline --graph --decorate --all "${@}"
}
FUNCTIONS_EOF

    log_info "Writing ~/.zsh/plugins.zsh ..."
    cat > "$HOME/.zsh/plugins.zsh" << 'PLUGINS_EOF'
# === AUTOSUGGESTIONS ===
if [[ -f ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

# === SYNTAX HIGHLIGHTING ===
if [[ -f ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

# === STARSHIP PROMPT ===
if command -v starship &> /dev/null; then
  eval "$(starship init zsh)"
fi
PLUGINS_EOF

    log_info "Writing tool modules into ~/.zsh/tools/ ..."

    cat > "$HOME/.zsh/tools/fzf.zsh" << 'FZF_EOF'
if command -v fzf &> /dev/null; then
  source <(fzf --zsh)
  export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border"
fi
FZF_EOF

    cat > "$HOME/.zsh/tools/zoxide.zsh" << 'ZOXIDE_EOF'
if command -v zoxide &> /dev/null; then
  eval "$(zoxide init zsh)"
  alias cd='z'
fi
ZOXIDE_EOF

    cat > "$HOME/.zsh/tools/node.zsh" << 'NODE_EOF'
# === NVM (lazy loading for fast startup) ===
export NVM_DIR="$HOME/.nvm"

lazy_nvm() {
  unset -f node npm npx nvm
  if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    source "$NVM_DIR/nvm.sh"
  fi
  if [[ -s "$NVM_DIR/bash_completion" ]]; then
    source "$NVM_DIR/bash_completion"
  fi
}

alias node='lazy_nvm && node'
alias npm='lazy_nvm && npm'
alias npx='lazy_nvm && npx'
alias nvm='lazy_nvm && nvm'
NODE_EOF

    cat > "$HOME/.zsh/tools/lsd.zsh" << 'LSD_EOF'
if command -v lsd &> /dev/null; then
  alias ls='lsd'
  alias ll='lsd -lh'
fi
LSD_EOF

    cat > "$HOME/.zsh/tools/java.zsh" << 'JAVA_EOF'
# === JAVA SETUP ===
if command -v java &> /dev/null; then
  export JAVA_HOME="$(dirname $(dirname $(readlink -f $(which java))))"
  typeset -U path
  path=($JAVA_HOME/bin $path)
fi
JAVA_EOF

    cat > "$HOME/.zsh/tools/conda.zsh" << 'CONDA_EOF'
# === CONDA AUTO-ACTIVE SETUP ===
export CONDA_DIR="$HOME/.local/miniconda3"

if [[ -f "$CONDA_DIR/bin/conda" ]]; then
  eval "$("$CONDA_DIR/bin/conda" shell.zsh hook)"
  if [[ "$CONDA_DEFAULT_ENV" != "base" ]]; then
    conda activate base
  fi
fi
CONDA_EOF

    log_ok "All ZSH config files written"

    # Install ZSH plugins via git
    if [[ ! -d "$HOME/.zsh/zsh-autosuggestions" ]]; then
        log_info "Cloning zsh-autosuggestions..."
        git clone --depth=1 \
            https://github.com/zsh-users/zsh-autosuggestions \
            "$HOME/.zsh/zsh-autosuggestions" 2>/dev/null \
            && log_ok "zsh-autosuggestions cloned" \
            || log_warn "zsh-autosuggestions clone failed"
    else
        log_ok "zsh-autosuggestions — already present"
    fi

    if [[ ! -d "$HOME/.zsh/zsh-syntax-highlighting" ]]; then
        log_info "Cloning zsh-syntax-highlighting..."
        git clone --depth=1 \
            https://github.com/zsh-users/zsh-syntax-highlighting \
            "$HOME/.zsh/zsh-syntax-highlighting" 2>/dev/null \
            && log_ok "zsh-syntax-highlighting cloned" \
            || log_warn "zsh-syntax-highlighting clone failed"
    else
        log_ok "zsh-syntax-highlighting — already present"
    fi

    # Set default shell
    local zsh_path
    zsh_path=$(which zsh 2>/dev/null || echo "")
    if [[ -z "$zsh_path" ]]; then
        log_warn "zsh binary not found; cannot set as default shell"
    elif [[ "$SHELL" == "$zsh_path" ]]; then
        log_ok "ZSH is already the default shell"
    else
        log_info "Setting ZSH as default shell..."
        grep -qF "$zsh_path" /etc/shells || echo "$zsh_path" | sudo tee -a /etc/shells > /dev/null
        chsh -s "$zsh_path" \
            && log_ok "Default shell → ZSH (takes effect on next login)" \
            || log_warn "chsh failed; set manually with: chsh -s $zsh_path"
    fi

    INSTALLED+=("zsh-config (modular: core aliases functions plugins + 6 tool modules)")
}

# ==============================================================================
# 3. STARSHIP PROMPT
# ==============================================================================
setup_starship() {
    log_section "Starship Prompt"

    if ! is_cmd starship; then
        log_info "Downloading and installing Starship..."
        curl -fsSL https://starship.rs/install.sh | sh -s -- --yes \
            && log_ok "Starship installed" \
            || { log_warn "Starship install failed"; return; }
    else
        log_ok "Starship — already installed ($(starship --version 2>/dev/null | head -1))"
    fi

    mkdir -p "$HOME/.config"
    log_info "Writing ~/.config/starship.toml ..."

    cat > "$HOME/.config/starship.toml" << 'STARSHIP_EOF'
[aws]
symbol = "  "

[buf]
symbol = " "

[c]
symbol = " "

[cmake]
symbol = " "

[conda]
symbol = " "

[crystal]
symbol = " "

[dart]
symbol = " "

[directory]
read_only = " 󰌾"

[docker_context]
symbol = " "

[elixir]
symbol = " "

[elm]
symbol = " "

[fennel]
symbol = " "

[fossil_branch]
symbol = " "

[git_branch]
symbol = " "

[git_commit]
tag_symbol = '  '

[golang]
symbol = " "

[guix_shell]
symbol = " "

[haskell]
symbol = " "

[haxe]
symbol = " "

[hg_branch]
symbol = " "

[hostname]
ssh_symbol = " "

[java]
symbol = " "

[julia]
symbol = " "

[kotlin]
symbol = " "

[lua]
symbol = " "

[memory_usage]
symbol = "󰍛 "

[meson]
symbol = "󰔷 "

[nim]
symbol = "󰆥 "

[nix_shell]
symbol = " "

[nodejs]
symbol = " "

[ocaml]
symbol = " "

[os.symbols]
Alpaquita = " "
Alpine = " "
AlmaLinux = " "
Amazon = " "
Android = " "
Arch = " "
Artix = " "
CachyOS = " "
CentOS = " "
Debian = " "
DragonFly = " "
Emscripten = " "
EndeavourOS = " "
Fedora = " "
FreeBSD = " "
Garuda = "󰛓 "
Gentoo = " "
HardenedBSD = "󰞌 "
Illumos = "󰈸 "
Kali = " "
Linux = " "
Mabox = " "
Macos = " "
Manjaro = " "
Mariner = " "
MidnightBSD = " "
Mint = " "
NetBSD = " "
NixOS = " "
Nobara = " "
OpenBSD = "󰈺 "
openSUSE = " "
OracleLinux = "󰌷 "
Pop = " "
Raspbian = " "
Redhat = " "
RedHatEnterprise = " "
RockyLinux = " "
Redox = "󰀘 "
Solus = "󰠳 "
SUSE = " "
Ubuntu = " "
Unknown = " "
Void = " "
Windows = "󰍲 "

[package]
symbol = "󰏗 "

[perl]
symbol = " "

[php]
symbol = " "

[pijul_channel]
symbol = " "

[python]
symbol = " "

[rlang]
symbol = "󰟔 "

[ruby]
symbol = " "

[rust]
symbol = "󱘗 "

[scala]
symbol = " "

[swift]
symbol = " "

[zig]
symbol = " "

[gradle]
symbol = " "
STARSHIP_EOF

    log_ok "~/.config/starship.toml written"
    INSTALLED+=("starship + starship.toml")
}

# ==============================================================================
# 4. MODERN CLI TOOLS (bat + lsd)
# ==============================================================================
setup_cli_tools() {
    log_section "Modern CLI Tools (bat + lsd)"

    # ── bat ──────────────────────────────────────────────────────────────────
    if is_cmd bat || is_cmd batcat; then
        log_ok "bat — already present"
    else
        log_info "Installing bat..."
        if [[ "$DISTRO_FAMILY" == "debian" ]]; then
            pkg_install bat 2>/dev/null || pkg_install batcat 2>/dev/null || true
        else
            pkg_install bat 2>/dev/null || true
        fi

        # On Debian/Ubuntu the binary is 'batcat'; create a local symlink
        if is_cmd batcat && ! is_cmd bat; then
            mkdir -p "$HOME/.local/bin"
            ln -sf "$(which batcat)" "$HOME/.local/bin/bat"
            log_ok "bat symlinked from batcat → ~/.local/bin/bat"
        elif is_cmd bat; then
            log_ok "bat installed"
        else
            log_warn "bat install failed; install manually: apt install bat"
        fi
    fi

    # ── lsd ──────────────────────────────────────────────────────────────────
    if is_cmd lsd; then
        log_ok "lsd — already present"
    else
        log_info "Installing lsd from GitHub releases..."
        local lsd_ver="1.1.5"
        local tmp_dir
        tmp_dir=$(mktemp -d)

        if [[ "$DISTRO_FAMILY" == "debian" ]]; then
            local deb_file="lsd_${lsd_ver}_amd64.deb"
            local deb_url="https://github.com/lsd-rs/lsd/releases/download/v${lsd_ver}/${deb_file}"
            curl -fsSL "$deb_url" -o "${tmp_dir}/${deb_file}" \
                && sudo dpkg -i "${tmp_dir}/${deb_file}" \
                && log_ok "lsd ${lsd_ver} installed" \
                || log_warn "lsd install failed; try: cargo install lsd"
        else
            local tar_file="lsd-${lsd_ver}-x86_64-unknown-linux-gnu.tar.gz"
            local tar_url="https://github.com/lsd-rs/lsd/releases/download/v${lsd_ver}/${tar_file}"
            curl -fsSL "$tar_url" -o "${tmp_dir}/${tar_file}" \
                && tar xzf "${tmp_dir}/${tar_file}" -C "${tmp_dir}/" \
                && sudo install -m 755 \
                    "${tmp_dir}/lsd-${lsd_ver}-x86_64-unknown-linux-gnu/lsd" \
                    /usr/local/bin/lsd \
                && log_ok "lsd ${lsd_ver} installed" \
                || log_warn "lsd install failed; try: cargo install lsd"
        fi

        rm -rf "$tmp_dir"
    fi

    INSTALLED+=("bat + lsd")
}

# ==============================================================================
# 5. TMUX CONFIG
# ==============================================================================
setup_tmux() {
    log_section "TMUX Configuration"

    log_info "Writing ~/.tmux.conf ..."
    cat > "$HOME/.tmux.conf" << 'TMUX_EOF'
# =============================================================================
# 1. ERGONOMIC PREFIX (Backtick)
# =============================================================================
set -g prefix `
bind ` send-prefix
unbind C-b

# =============================================================================
# 2. CORE SETTINGS
# =============================================================================
set -g default-terminal "screen-256color"
set-option -g terminal-overrides ',xterm-256color:RGB'
set -g base-index 1
set -g detach-on-destroy off
set -s escape-time 0
set -g history-limit 1000000
set -g renumber-windows on
set -g set-clipboard on
set -g status-position top
setw -g mode-keys vi
set -g mouse on

# =============================================================================
# 3. COLORFUL THEME & DYNAMIC CHEAT SHEET
# =============================================================================
set -g pane-active-border-style 'fg=magenta,bg=default'
set -g pane-border-style 'fg=brightblack,bg=default'
set -g status-style 'bg=default'

# LEFT: Rainbow pill shortcut reference
set -g status-left-length 300
set -g status-left "#[fg=cyan,bold] #S #[fg=brightblack]#[fg=white,bg=brightblack,bold]#[fg=green]\`+(-)#[fg=white]:Split #[fg=yellow]\`(Arr)#[fg=white]:Size #[fg=magenta]\`*#[fg=white]:Zoom #[fg=red]\`/#[fg=white]:Close #[fg=blue]Num#[fg=white]:Win #[fg=brightblack,bg=default]"

# RIGHT: Gradient directory & time
set -g status-right-length 70
set -g status-right "#[fg=brightblack]#[fg=white,bg=brightblack] %H:%M #[fg=cyan,bg=brightblack]#[fg=black,bg=cyan,bold] #{b:pane_current_path} #[fg=cyan,bg=default]"

# =============================================================================
# WINDOW TABS: Minimal & Transparent
# =============================================================================
set -g status-justify centre
set -g window-status-format         "#[fg=brightblack,bg=default] #I:#W "
set -g window-status-current-format "#[fg=magenta,bg=default,bold,underscore] #I:#W "

# =============================================================================
# 4. KEYBINDINGS
# =============================================================================
bind r source-file ~/.tmux.conf \; display "Config Reloaded!"

# Pane navigation (vim-style)
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# Resize panes (repeatable)
bind -r Up    resize-pane -U 5
bind -r Down  resize-pane -D 5
bind -r Left  resize-pane -L 5
bind -r Right resize-pane -R 5

# Splits using numpad-style keys (requires prefix)
bind + split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
bind * resize-pane -Z
bind / confirm-before -p "Kill pane? (y/n)" kill-pane

# Alias splits
bind v split-window -h -c "#{pane_current_path}"
bind s split-window -v -c "#{pane_current_path}"
bind z resize-pane -Z
bind x kill-pane
bind ^C new-window -c "$HOME"
bind K send-keys "clear"\; send-keys "Enter"

# =============================================================================
# 5. NUMPAD WINDOW SWITCHING (No prefix needed)
# =============================================================================
bind-key -n KP1 select-window -t 1
bind-key -n KP2 select-window -t 2
bind-key -n KP3 select-window -t 3
bind-key -n KP4 select-window -t 4
bind-key -n KP5 select-window -t 5
bind-key -n KP6 select-window -t 6
bind-key -n KP7 select-window -t 7
bind-key -n KP8 select-window -t 8
bind-key -n KP9 select-window -t 9

# =============================================================================
# 6. CLEANUP
# =============================================================================
unbind %
unbind '"'
TMUX_EOF

    log_ok "~/.tmux.conf written"
    INSTALLED+=("tmux-config (backtick prefix, vi-keys, mouse, rainbow theme)")
}

# ==============================================================================
# 6. DROPDOWN TERMINAL
# ==============================================================================
setup_dropdown_terminal() {
    log_section "Dropdown Terminal"

    local installed_term=""

    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        if is_cmd guake; then
            log_ok "Guake — already installed"
            installed_term="guake"
        else
            log_info "Installing Guake..."
            pkg_install guake \
                && log_ok "Guake installed" \
                && installed_term="guake" \
                || log_warn "Guake install failed"
        fi
    else
        # Fedora: prefer yakuake (KDE), fallback guake
        if is_cmd yakuake; then
            log_ok "Yakuake — already installed"
            installed_term="yakuake"
        elif is_cmd guake; then
            log_ok "Guake — already installed"
            installed_term="guake"
        else
            log_info "Installing Yakuake (KDE) ..."
            if pkg_install yakuake 2>/dev/null; then
                log_ok "Yakuake installed"
                installed_term="yakuake"
            else
                log_info "Yakuake unavailable, trying Guake..."
                pkg_install guake \
                    && log_ok "Guake installed" \
                    && installed_term="guake" \
                    || log_warn "No dropdown terminal could be installed"
            fi
        fi
    fi

    # Autostart for guake (XDG)
    if [[ "$installed_term" == "guake" ]]; then
        mkdir -p "$HOME/.config/autostart"
        cat > "$HOME/.config/autostart/guake.desktop" << 'GUAKE_AUTOSTART'
[Desktop Entry]
Name=Guake Terminal
Comment=Use the F12 key to show/hide the terminal
Exec=guake
Terminal=false
Type=Application
Categories=GNOME;GTK;Utility;TerminalEmulator;
StartupNotify=false
X-GNOME-Autostart-enabled=true
GUAKE_AUTOSTART
        log_ok "Guake autostart entry written to ~/.config/autostart/"
    fi

    [[ -n "$installed_term" ]] && INSTALLED+=("dropdown-terminal ($installed_term)")
}

# ==============================================================================
# 7. QUTEBROWSER
# ==============================================================================
setup_qutebrowser() {
    log_section "Qutebrowser"

    if ! is_cmd qutebrowser; then
        log_info "Installing qutebrowser..."
        pkg_install qutebrowser \
            && log_ok "qutebrowser installed" \
            || log_warn "qutebrowser install failed; try flatpak install qutebrowser"
    else
        log_ok "qutebrowser — already installed"
    fi

    mkdir -p "$HOME/.config/qutebrowser"
    log_info "Writing ~/.config/qutebrowser/config.py ..."

    cat > "$HOME/.config/qutebrowser/config.py" << 'QUTE_EOF'
# Qutebrowser config optimized for reading and research

# Load autoconfig (required)
config.load_autoconfig()

# ===== ADBLOCKER — Enhanced with YouTube ad blocking =====
c.content.blocking.enabled = True
c.content.blocking.adblock.lists = [
    # Core
    "https://easylist.to/easylist/easylist.txt",
    # Privacy
    "https://easylist.to/easylist/easyprivacy.txt",
    # Annoyances
    "https://secure.fanboy.co.nz/fanboy-annoyance.txt",
    # uBlock Origin filters
    "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt",
    "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/privacy.txt",
    "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/unbreak.txt",
    "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/badware.txt",
    "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/annoyances.txt",
    "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/resource-abuse.txt",
    "https://www.i-dont-care-about-cookies.eu/abp/",
    # Anti-adblock bypass
    "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/quick-fixes.txt",
]

# ===== CLEAN UI FOR READING =====
c.window.hide_decoration = True
c.tabs.show = "multiple"
c.statusbar.show = "in-mode"
c.scrolling.bar = "when-searching"
c.scrolling.smooth = True

# ===== FONTS & READABILITY =====
c.fonts.default_size = "14pt"
c.fonts.web.family.standard = "Georgia, serif"
c.fonts.web.family.serif = "Georgia, serif"
c.fonts.web.family.sans_serif = "Arial, sans-serif"

# ===== PRIVACY =====
c.content.cookies.accept = "no-3rdparty"
c.content.headers.do_not_track = True

# ===== SEARCH ENGINES =====
c.url.searchengines = {
    # General
    'DEFAULT':    'https://duckduckgo.com/?q={}',
    'google':     'https://www.google.com/search?q={}',
    'bing':       'https://www.bing.com/search?q={}',
    # Dev
    'gfg':        'https://www.geeksforgeeks.org/search/?q={}',
    'java':       'https://docs.oracle.com/en/java/javase/17/docs/api/search.html?q={}',
    # Media
    'yt':         'https://www.youtube.com/results?search_query={}',
    # ML / Data Science
    'scikit':     'https://scikit-learn.org/stable/search.html?q={}',
    'seaborn':    'https://seaborn.pydata.org/search.html?q={}',
    'kaggle':     'https://www.kaggle.com/search?q={}',
    # AI
    'chatgpt':    'https://chat.openai.com/?q={}',
    'claude':     'https://claude.ai/chat/{}',
    'perplexity': 'https://www.perplexity.ai/search?q={}',
    'searx':      'https://searx.org/search?q={}',
}

# ===== TAB KEYBINDINGS =====
for i in range(1, 10):
    config.bind(f'<Alt+{i}>', f'tab-focus {i}')

c.tabs.close_mouse_button = 'middle'
config.bind('<Ctrl+Tab>',       'tab-next')
config.bind('<Ctrl+Shift+Tab>', 'tab-prev')
config.bind('<Ctrl+w>',         'tab-close')

# ===== COMPLETION =====
c.completion.open_categories = ['bookmarks', 'searchengines', 'history']
c.completion.height = '60%'
c.completion.delay = 0
c.completion.use_best_match = True
config.bind('b', 'set-cmd-text -s :tab-select')

# ===== TAB FONTS =====
c.fonts.tabs.selected   = "14pt default_family"
c.fonts.tabs.unselected = "14pt default_family"

# ===== TAB COLORS =====
c.colors.tabs.selected.even.bg = '#ff6b35'
c.colors.tabs.selected.even.fg = '#000000'
c.colors.tabs.selected.odd.bg  = '#ff6b35'
c.colors.tabs.selected.odd.fg  = '#000000'

c.colors.tabs.even.bg = '#2d2d2d'
c.colors.tabs.even.fg = '#cccccc'
c.colors.tabs.odd.bg  = '#3d3d3d'
c.colors.tabs.odd.fg  = '#cccccc'

c.colors.tabs.indicator.error  = '#ff4757'
c.colors.tabs.indicator.system = 'rgb'

c.colors.tabs.pinned.selected.even.bg = '#2ecc71'
c.colors.tabs.pinned.selected.even.fg = '#ffffff'
c.colors.tabs.pinned.selected.odd.bg  = '#2ecc71'
c.colors.tabs.pinned.selected.odd.fg  = '#ffffff'

# ===== SESSION =====
c.session.default_name = 'default'
c.auto_save.session = True

# ===== DOWNLOADS =====
c.downloads.location.prompt = False
QUTE_EOF

    log_ok "~/.config/qutebrowser/config.py written"
    INSTALLED+=("qutebrowser + config.py")
}

# ==============================================================================
# 8. ZOXIDE
# ==============================================================================
setup_zoxide() {
    log_section "Zoxide (Smart cd)"

    if is_cmd zoxide; then
        log_ok "zoxide — already installed ($(zoxide --version 2>/dev/null))"
    else
        log_info "Installing zoxide via official install script..."
        curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash \
            && log_ok "zoxide installed" \
            || log_warn "zoxide install failed; try: cargo install zoxide"
    fi

    INSTALLED+=("zoxide")
}

# ==============================================================================
# 9. NVM / NODE
# ==============================================================================
setup_nvm() {
    log_section "NVM (Node Version Manager)"

    if [[ -d "$HOME/.nvm" ]] && [[ -s "$HOME/.nvm/nvm.sh" ]]; then
        log_ok "NVM — already installed at ~/.nvm"
    else
        log_info "Installing NVM v0.40.1..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash \
            && log_ok "NVM installed" \
            || log_warn "NVM install failed"
    fi

    INSTALLED+=("nvm (lazy-loaded via ~/.zsh/tools/node.zsh)")
}

# ==============================================================================
# 10. VS CODE
# ==============================================================================
install_vscode() {
    log_section "Visual Studio Code"

    if is_cmd code; then
        log_ok "VS Code — already installed"
        INSTALLED+=("vscode")
        return
    fi

    log_info "Installing VS Code..."
    require_sudo

    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        local tmp_gpg="/tmp/packages.microsoft.gpg"
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
            | gpg --dearmor > "$tmp_gpg"
        sudo install -D -o root -g root -m 644 \
            "$tmp_gpg" /etc/apt/keyrings/packages.microsoft.gpg
        echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] \
https://packages.microsoft.com/repos/code stable main" \
            | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
        sudo apt-get update -y &>/dev/null
        pkg_install code && log_ok "VS Code installed" || log_warn "VS Code install failed"
        rm -f "$tmp_gpg"
    else
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        cat << 'VSCODE_REPO' | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
VSCODE_REPO
        pkg_install code && log_ok "VS Code installed" || log_warn "VS Code install failed"
    fi

    INSTALLED+=("vscode")
}

# ==============================================================================
# 11. GOOGLE CHROME
# ==============================================================================
install_chrome() {
    log_section "Google Chrome"

    if is_cmd google-chrome-stable || is_cmd google-chrome; then
        log_ok "Google Chrome — already installed"
        INSTALLED+=("google-chrome")
        return
    fi

    log_info "Installing Google Chrome..."
    require_sudo

    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        local tmp_deb="/tmp/google-chrome-stable.deb"
        curl -fsSL "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" \
            -o "$tmp_deb" \
            && sudo apt-get install -y "$tmp_deb" \
            && log_ok "Google Chrome installed" \
            || log_warn "Chrome install failed"
        rm -f "$tmp_deb"
    else
        cat << 'CHROME_REPO' | sudo tee /etc/yum.repos.d/google-chrome.repo > /dev/null
[google-chrome]
name=google-chrome
baseurl=http://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
CHROME_REPO
        pkg_install google-chrome-stable \
            && log_ok "Google Chrome installed" \
            || log_warn "Chrome install failed"
    fi

    INSTALLED+=("google-chrome")
}

# ==============================================================================
# 12. MICROSOFT EDGE
# ==============================================================================
install_edge() {
    log_section "Microsoft Edge"

    if is_cmd microsoft-edge-stable || is_cmd microsoft-edge; then
        log_ok "Microsoft Edge — already installed"
        INSTALLED+=("microsoft-edge")
        return
    fi

    log_info "Installing Microsoft Edge..."
    require_sudo

    if [[ "$DISTRO_FAMILY" == "debian" ]]; then
        curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
            | gpg --dearmor \
            | sudo tee /usr/share/keyrings/microsoft-edge.gpg > /dev/null
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-edge.gpg] \
https://packages.microsoft.com/repos/edge stable main" \
            | sudo tee /etc/apt/sources.list.d/microsoft-edge.list > /dev/null
        sudo apt-get update -y &>/dev/null
        pkg_install microsoft-edge-stable \
            && log_ok "Edge installed" \
            || log_warn "Edge install failed"
    else
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        cat << 'EDGE_REPO' | sudo tee /etc/yum.repos.d/microsoft-edge.repo > /dev/null
[microsoft-edge]
name=microsoft-edge
baseurl=https://packages.microsoft.com/yumrepos/edge
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EDGE_REPO
        pkg_install microsoft-edge-stable \
            && log_ok "Edge installed" \
            || log_warn "Edge install failed"
    fi

    INSTALLED+=("microsoft-edge")
}

# ==============================================================================
# 13. JETBRAINS TOOLBOX
# ==============================================================================
install_jetbrains() {
    log_section "JetBrains Toolbox"

    local toolbox_bin="$HOME/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox"
    if [[ -f "$toolbox_bin" ]]; then
        log_ok "JetBrains Toolbox — already installed"
        INSTALLED+=("jetbrains-toolbox")
        return
    fi

    log_info "Fetching latest JetBrains Toolbox release URL..."
    local jb_url
    jb_url=$(curl -fsSL \
        'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release' \
        2>/dev/null \
        | grep -oP '"linux":\s*"\K[^"]+' \
        | head -1)

    if [[ -z "$jb_url" ]]; then
        log_warn "Could not fetch JetBrains Toolbox download URL. Visit: https://www.jetbrains.com/toolbox-app/"
        return
    fi

    log_info "Downloading JetBrains Toolbox..."
    local tmp_dir
    tmp_dir=$(mktemp -d)
    curl -fsSL "$jb_url" -o "${tmp_dir}/toolbox.tar.gz" \
        && tar xzf "${tmp_dir}/toolbox.tar.gz" -C "${tmp_dir}/"

    local extracted_bin
    extracted_bin=$(find "${tmp_dir}" -name "jetbrains-toolbox" -type f | head -1)

    if [[ -n "$extracted_bin" ]]; then
        chmod +x "$extracted_bin"
        log_info "Launching JetBrains Toolbox (will self-install) ..."
        "$extracted_bin" &
        disown
        log_ok "JetBrains Toolbox launched successfully"
        INSTALLED+=("jetbrains-toolbox")
    else
        log_warn "Toolbox binary not found in archive"
    fi

    rm -rf "$tmp_dir"
}

# ==============================================================================
# SUMMARY
# ==============================================================================
print_summary() {
    echo ""
    echo -e "${BOLD}${CYAN}"
    echo "  ╔═══════════════════════════════════════════════╗"
    echo "  ║           INSTALLATION COMPLETE               ║"
    echo "  ╚═══════════════════════════════════════════════╝"
    echo -e "${RESET}"

    if [[ ${#INSTALLED[@]} -gt 0 ]]; then
        echo -e "  ${GREEN}${BOLD}Installed / Configured:${RESET}"
        for item in "${INSTALLED[@]}"; do
            echo -e "    ${GREEN}✔${RESET}  $item"
        done
    fi

    if [[ ${#SKIPPED[@]} -gt 0 ]]; then
        echo ""
        echo -e "  ${YELLOW}${BOLD}Skipped:${RESET}"
        for item in "${SKIPPED[@]}"; do
            echo -e "    ${YELLOW}✖${RESET}  $item"
        done
    fi

    echo ""
    echo -e "  ${BOLD}${BLUE}╔══ Next Steps ═══════════════════════════════════╗${RESET}"
    echo -e "  ${BLUE}║${RESET}  1. Log out and back in (or reboot) for ZSH     ${BLUE}║${RESET}"
    echo -e "  ${BLUE}║${RESET}     to become default shell                      ${BLUE}║${RESET}"
    echo -e "  ${BLUE}║${RESET}  2. Install a Nerd Font for Starship & lsd icons ${BLUE}║${RESET}"
    echo -e "  ${BLUE}║${RESET}     → https://www.nerdfonts.com/                 ${BLUE}║${RESET}"
    echo -e "  ${BLUE}║${RESET}  3. In TMUX: prefix is now backtick (\`)          ${BLUE}║${RESET}"
    echo -e "  ${BLUE}║${RESET}  4. After shell reload, run: nvm install --lts   ${BLUE}║${RESET}"
    echo -e "  ${BLUE}║${RESET}  5. For qutebrowser adblock: open and press      ${BLUE}║${RESET}"
    echo -e "  ${BLUE}║${RESET}     :adblock-update                              ${BLUE}║${RESET}"
    echo -e "  ${BOLD}${BLUE}╚═════════════════════════════════════════════════╝${RESET}"
    echo ""
}

# ==============================================================================
# MAIN
# ==============================================================================
main() {
    clear
    echo -e "${BOLD}${CYAN}"
    cat << 'BANNER'

    ██████╗ ███████╗██╗   ██╗███████╗███╗   ██╗██╗   ██╗
    ██╔══██╗██╔════╝██║   ██║██╔════╝████╗  ██║██║   ██║
    ██║  ██║█████╗  ██║   ██║█████╗  ██╔██╗ ██║██║   ██║
    ██║  ██║██╔══╝  ╚██╗ ██╔╝██╔══╝  ██║╚██╗██║╚██╗ ██╔╝
    ██████╔╝███████╗ ╚████╔╝ ███████╗██║ ╚████║ ╚████╔╝
    ╚═════╝ ╚══════╝  ╚═══╝  ╚══════╝╚═╝  ╚═══╝  ╚═══╝

       Linux Dev Environment Bootstrap  —  v1.0
BANNER
    echo -e "${RESET}"

    detect_os

    echo ""
    echo -e "  ${DIM}This script will interactively set up your dev environment.${RESET}"
    echo -e "  ${DIM}All steps are idempotent — safe to run multiple times.${RESET}"
    echo ""

    # ── Always: base packages ──────────────────────────────────────────────
    install_base

    # ── ZSH ───────────────────────────────────────────────────────────────
    if ask "Configure ZSH? (modular config, autosuggestions, syntax highlighting)"; then
        setup_zsh
    else
        log_skip "ZSH config"
        SKIPPED+=("zsh-config")
    fi

    # ── Starship ──────────────────────────────────────────────────────────
    if ask "Install Starship prompt + Nerd Font icon config?"; then
        setup_starship
    else
        log_skip "Starship"
        SKIPPED+=("starship")
    fi

    # ── Modern CLI (bat + lsd) ────────────────────────────────────────────
    if ask "Install modern CLI tools? (bat for cat, lsd for ls)"; then
        setup_cli_tools
    else
        log_skip "bat + lsd"
        SKIPPED+=("bat + lsd")
    fi

    # ── TMUX ──────────────────────────────────────────────────────────────
    if ask "Write TMUX config? (backtick prefix, vi keys, mouse, custom theme)"; then
        setup_tmux
    else
        log_skip "TMUX config"
        SKIPPED+=("tmux-config")
    fi

    # ── Dropdown terminal ─────────────────────────────────────────────────
    if ask "Install dropdown terminal? (Guake on Debian / Yakuake on Fedora)"; then
        setup_dropdown_terminal
    else
        log_skip "Dropdown terminal"
        SKIPPED+=("dropdown-terminal")
    fi

    # ── Qutebrowser ───────────────────────────────────────────────────────
    if ask "Install and configure Qutebrowser? (adblock, custom search engines, orange tabs)"; then
        setup_qutebrowser
    else
        log_skip "Qutebrowser"
        SKIPPED+=("qutebrowser")
    fi

    # ── Zoxide ────────────────────────────────────────────────────────────
    if ask "Install zoxide? (smart cd replacement, aliased as 'cd')"; then
        setup_zoxide
    else
        log_skip "Zoxide"
        SKIPPED+=("zoxide")
    fi

    # ── NVM ───────────────────────────────────────────────────────────────
    if ask "Install NVM? (lazy-loaded Node Version Manager)"; then
        setup_nvm
    else
        log_skip "NVM"
        SKIPPED+=("nvm")
    fi

    echo ""
    log_section "Developer Applications"

    # ── VS Code ───────────────────────────────────────────────────────────
    if ask "Install Visual Studio Code?"; then
        install_vscode
    else
        log_skip "VS Code"
        SKIPPED+=("vscode")
    fi

    # ── Chrome ────────────────────────────────────────────────────────────
    if ask "Install Google Chrome?"; then
        install_chrome
    else
        log_skip "Google Chrome"
        SKIPPED+=("google-chrome")
    fi

    # ── Edge ──────────────────────────────────────────────────────────────
    if ask "Install Microsoft Edge?"; then
        install_edge
    else
        log_skip "Microsoft Edge"
        SKIPPED+=("microsoft-edge")
    fi

    # ── JetBrains Toolbox ─────────────────────────────────────────────────
    if ask "Install JetBrains Toolbox? (launches and self-installs)"; then
        install_jetbrains
    else
        log_skip "JetBrains Toolbox"
        SKIPPED+=("jetbrains-toolbox")
    fi

    print_summary
}

main "$@"
