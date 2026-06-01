#!/usr/bin/env bash
set -euo pipefail

# Odmah očisti ekran pri pokretanju
clear

########################################
# BOJE I FORMATIRANJE
########################################

CRVENA='\033[0;31m'
ZELENA='\033[0;32m'
ZUTA='\033[1;33m'
PLAVA='\033[0;34m'
NC='\033[0m' # Bez boje

log_info()    { echo -e "${PLAVA}[INFO]${NC}  $1"; }
log_ok()      { echo -e "${ZELENA}[U SPEH]${NC} $1"; }
log_warn()    { echo -e "${ZUTA}[PAŽNJA]${NC} $1"; }
log_error()   { echo -e "${CRVENA}[GREŠKA]${NC} $1"; }

########################################
# Provera i pokretanje kao Root
########################################

if [ "$EUID" -ne 0 ]; then
    exec sudo -E bash "$0" "$@"
fi

log_info "Pokretanje instalacije i podešavanja sistema..."
echo "--------------------------------------------------"

########################################
# Pomoćne funkcije
########################################

backup_file() {
    local f="$1"
    [ -f "$f" ] && cp "$f" "${f}.bak"
}

########################################
# 1. oFono podešavanje
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
        log_info "[oFono] Dodavanje operatorskog bloka..."
        backup_file "$OFONO_FILE"
        printf "\n%s\n" "$OFONO_BLOCK" >> "$OFONO_FILE"
        log_ok "[oFono] Konfiguracija je uspešno ažurirana."
    else
        log_ok "[oFono] Već je konfigurisan."
    fi
else
    log_error "[oFono] Datoteka ne postoji: $OFONO_FILE"
    exit 1
fi

echo "--------------------------------------------------"

########################################
# 2. ConnMan konfiguracija
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
    log_info "[ConnMan] Konfigurisanje mrežnih tehnologija..."

    backup_file "$CONNMAN_FILE"

    update_or_add "DefaultAutoConnectTechnologies" "$VALUE"
    update_or_add "PreferredTechnologies" "$VALUE"

    log_ok "[ConnMan] Konfiguracija je uspešno ažurirana."
else
    log_error "[ConnMan] Datoteka ne postoji: $CONNMAN_FILE"
    exit 1
fi

echo "--------------------------------------------------"

########################################
# 3. LoRa Forwarder konfiguracija
########################################

log_info "[LoRa] Unesite podatke za konfiguraciju forwarder-a:"

read -rp "$(echo -e ${PLAVA}Adresa servera:${NC} ) " SERVER
: "${SERVER:?Adresa servera je obavezna!}"

read -rp "$(echo -e ${PLAVA}Uplink port [1700]:${NC} ) " UPLINK_PORT
read -rp "$(echo -e ${PLAVA}Downlink port [1700]:${NC} ) " DOWNLINK_PORT

UPLINK_PORT=${UPLINK_PORT:-1700}
DOWNLINK_PORT=${DOWNLINK_PORT:-1700}

log_info "[LoRa] Pokretanje 'lorafwdctl' i primena podešavanja..."

lorafwdctl -s gwmp.node "$SERVER"
lorafwdctl gwmp.service.uplink "$UPLINK_PORT"
lorafwdctl gwmp.service.downlink "$DOWNLINK_PORT"

log_ok "[LoRa] Uspešno konfigurisan."

echo "--------------------------------------------------"

########################################
# 4. systemd servis
########################################

log_info "[systemd] Aktivacija i pokretanje lorafwd servisa..."

systemctl enable --now lorafwd

log_ok "[systemd] Servis je uspešno pokrenut i dodat u auto-start."

########################################
# 5. Kraj i Ponovno pokretanje
########################################

echo ""
echo "=================================================="
log_ok "Instalacija i podešavanje su završeni!"
echo "=================================================="
echo ""

read -rp "$(echo -e ${ZUTA}Da li želite da ponovo pokrenete sistem (reboot) sada? [y/N]:${NC} ) " ans

if [[ "${ans,,}" == "y" ]]; then
    echo ""
    log_warn "Sistem se ponovo pokreće za 5 sekundi..."
    sleep 5
    reboot
else
    log_info "Instalacija završena bez ponovnog pokretanja."
fi