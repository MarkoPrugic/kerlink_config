#!/usr/bin/env bash
set -euo pipefail

########################################
# COLORS
########################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # no color

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()      { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

########################################
# Root normalization
########################################

if [ "$EUID" -ne 0 ]; then
    exec sudo -E bash "$0" "$@"
fi

log_info "Deployment installer start"

########################################
# Helpers
########################################

backup_file() {
    local f="$1"
    [ -f "$f" ] && cp "$f" "${f}.bak"
}

########################################
# 1. oFono provisioning
########################################

OFONO_FILE="/etc/network/ofono/provisioning"

OFONO_BLOCK='[operator:220,05]
internet.AccessPointName = internet
internet.Username = internet
internet.Password = internet
internet.AuthenticationMethod = chap
internet.Protocol = ip
'

if [ -f "$OFONO_FILE" ]; then
    if ! grep -q "^\[operator:220,05\]" "$OFONO_FILE"; then
        log_info "[oFono] adding operator block"
        backup_file "$OFONO_FILE"
        printf "\n%s\n" "$OFONO_BLOCK" >> "$OFONO_FILE"
        log_ok "[oFono] updated"
    else
        log_ok "[oFono] already configured"
    fi
else
    log_error "[oFono] missing file: $OFONO_FILE"
    exit 1
fi

########################################
# 2. ConnMan configuration
########################################

CONNMAN_FILE="/etc/network/connman/main.conf"
VALUE="ethernet,wifi,cellular"

update_or_add() {
    local key="$1"
    local value="$2"

    if grep -q "^$key=" "$CONNMAN_FILE"; then
        sed -i "s|^$key=.*|$key=$value|" "$CONNMAN_FILE"
    else
        echo "$key=$value" >> "$CONNMAN_FILE"
    fi
}

if [ -f "$CONNMAN_FILE" ]; then
    log_info "[ConnMan] configuring"

    backup_file "$CONNMAN_FILE"

    update_or_add "DefaultAutoConnectTechnologies" "$VALUE"
    update_or_add "PreferredTechnologies" "$VALUE"

    log_ok "[ConnMan] updated"
else
    log_error "[ConnMan] missing file: $CONNMAN_FILE"
    exit 1
fi

########################################
# 3. LoRa Forwarder config
########################################

read -rp "$(echo -e ${BLUE}Server address:${NC} ) " SERVER
: "${SERVER:?Server address required}"

read -rp "$(echo -e ${BLUE}Uplink port [1700]:${NC} ) " UPLINK_PORT
read -rp "$(echo -e ${BLUE}Downlink port [1700]:${NC} ) " DOWNLINK_PORT

UPLINK_PORT=${UPLINK_PORT:-1700}
DOWNLINK_PORT=${DOWNLINK_PORT:-1700}

log_info "[LoRa] configuring forwarder"

lorafwdctl -s gwmp.node "$SERVER"
lorafwdctl gwmp.service.uplink "$UPLINK_PORT"
lorafwdctl gwmp.service.downlink "$DOWNLINK_PORT"

log_ok "[LoRa] configured"

########################################
# 4. systemd service
########################################

log_info "[systemd] enabling lorafwd"

systemctl enable --now lorafwd

log_ok "[systemd] service enabled"

########################################
# 5. finish
########################################

echo ""
log_ok "Deployment complete"

read -rp "$(echo -e ${YELLOW}Reboot now? [y/N]:${NC} ) " ans

if [[ "${ans,,}" == "y" ]]; then
    log_warn "Rebooting in 5 seconds..."
    sleep 5
    reboot
fi