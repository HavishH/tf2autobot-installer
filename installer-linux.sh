#!/usr/bin/env bash

set -uo pipefail

RED='\033[0;31m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

wait_for_exit=false
for arg in "$@"; do
    [ "$arg" = "--wait-for-exit" ] && wait_for_exit=true
done

write_step() {
    echo ""
    echo -e "${CYAN}> $1${NC}"
}

pause_before_exit() {
    if $wait_for_exit; then
        echo ""
        echo -e "${GRAY}Press Enter to close this window...${NC}"
        read -r < /dev/tty 2>/dev/null || true
    fi
}

fail() {
    echo ""
    echo -e "${RED}ERROR: $1${NC}"
    pause_before_exit
    exit 1
}

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    command -v sudo >/dev/null 2>&1 || fail "This needs root privileges to install packages, and sudo isn't available. Re-run as root"
    SUDO="sudo"
fi

if command -v apt-get >/dev/null 2>&1; then
    pkg_manager="apt"
elif command -v dnf >/dev/null 2>&1; then
    pkg_manager="dnf"
elif command -v pacman >/dev/null 2>&1; then
    pkg_manager="pacman"
else
    fail "Couldn't detect apt, dnf, or pacman on this system, unsupported distro"
fi

write_step "Choose install location"

default_path="$HOME/tf2autobot"
if [ -r /dev/tty ]; then
    read -rp "Where do you want to install TF2Autobot? [$default_path]: " install_path < /dev/tty
else
    echo "No interactive terminal detected, using default location"
    install_path=""
fi
install_path="${install_path:-$default_path}"

echo "Installing to: $install_path"

if [ -e "$install_path" ]; then
    fail "That folder already exists. Choose an empty/nonexistent path"
fi

write_step "Installing Git"

if command -v git >/dev/null 2>&1; then
    echo "Git already installed"
else
    case "$pkg_manager" in
        apt)
            $SUDO apt-get update -y || fail "apt-get update failed"
            $SUDO apt-get install -y git
            ;;
        dnf)
            $SUDO dnf install -y git
            ;;
        pacman)
            $SUDO pacman -Syu --noconfirm --needed git
            ;;
    esac
    [ $? -eq 0 ] || fail "Git install failed"
fi

write_step "Installing Node.js (LTS)"

if command -v node >/dev/null 2>&1; then
    echo "Node already installed"
else
    node_major=24
    export NVM_DIR="$HOME/.nvm"

    if [ ! -s "$NVM_DIR/nvm.sh" ]; then
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.6/install.sh | bash \
            || fail "Installing nvm failed"
    fi

    \. "$NVM_DIR/nvm.sh"

    echo "Installing Node.js $node_major.x"
    nvm install "$node_major" || fail "Node install failed"
    nvm alias default "$node_major" >/dev/null
fi

for tool in git node npm; do
    command -v "$tool" >/dev/null 2>&1 || fail "'$tool' is not available after installation"
done

echo ""
echo "Git:  $(git --version)"
echo "Node: $(node --version)"
echo "npm:  $(npm --version)"
echo ""

write_step "Cloning TF2Autobot"

git clone https://github.com/TF2Autobot/tf2autobot "$install_path" || fail "git clone failed"

cd "$install_path" || fail "Couldn't enter $install_path"

write_step "Installing TypeScript"
npm install typescript@latest -g || fail "Installing TypeScript failed"

write_step "Installing PM2"
npm install pm2@latest -g || fail "Installing PM2 failed"

write_step "Installing dependencies"
npm ci --no-audit || fail "npm ci failed"

write_step "Building TF2Autobot"
npm run build || fail "Build failed"

write_step "Creating ecosystem.json"
cp "./template.ecosystem.json" "./ecosystem.json" || fail "Couldn't create ecosystem.json"
echo "Created ecosystem.json"

write_step "Done"

echo "TF2Autobot installed"
echo "Location: $install_path"
echo ""
echo "Edit ecosystem.json and add your bot credentials"
echo "Config guide:"
echo "https://github.com/TF2Autobot/tf2autobot/wiki/Configuring-the-bot"
echo ""
echo -n "Start your bot with: "
echo -e "${CYAN}pm2 start ecosystem.json${NC}"

pause_before_exit