#!/usr/bin/env bash
set -euo pipefail

########################################
# KERLINK GATEWAY KONFIGURACIJA - GUI
# LoRaWAN Gateway - Sistemska Administracija
########################################

if [ "$EUID" -ne 0 ]; then
    exec sudo -E bash "$0" "$@"
fi

########################################
# FORMATIRANJE I BOJE
########################################

readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[1;33m'
readonly BLUE=$'\033[0;34m'
readonly CYAN=$'\033[0;36m'
readonly MAGENTA=$'\033[0;35m'
readonly WHITE=$'\033[1;37m'
readonly GRAY=$'\033[0;90m'
readonly NC=$'\033[0m'
readonly BOLD=$'\033[1m'
readonly DIM=$'\033[2m'

readonly OFONO_FILE="/etc/network/ofono/provisioning"
readonly CONNMAN_FILE="/etc/network/connman/main.conf"

SELECTED_MENU=0
TOTAL_MENU_ITEMS=0
declare -a MENU_OPTIONS=()
declare -a STEPS_DONE=()

########################################
# LOGGING FUNCTIONS
########################################

log_info()  { printf "%b%-12s%b %s\n" "${BLUE}[*]${NC}" "" "${NC}" "$1"; }
log_ok()    { printf "%b%-12s%b %s\n" "${GREEN}[+]${NC}" "" "${NC}" "$1"; }
log_warn()  { printf "%b%-12s%b %s\n" "${YELLOW}[!]${NC}" "" "${NC}" "$1"; }
log_error() { printf "%b%-12s%b %s\n" "${RED}[-]${NC}" "" "${NC}" "$1"; }

########################################
# UTILITY FUNCTIONS
########################################

backup_file() {
    local f="$1"
    if [ -f "$f" ]; then
        cp "$f" "${f}.bak"
        log_info "Backup: ${f}.bak"
    fi
}

clear_screen() {
    printf "\033[2J\033[H"
}

print_header() {
    clear_screen
    printf "%b" "${BOLD}${CYAN}"
\n"    printf "
                KERLINK GATEWAY CONFIGURATION \n"UTILITY             printf "
                      LoRaWAN Gateway \n"Management                  printf "
\n"    printf "
    printf "%b\n" "${NC}"
}

print_separator() {
    printf "%b" "${GRAY}"
\n"    printf "
    printf "%b" "${NC}"
}

print_menu_item() {
    local index="$1"
    local label="$2"
    local status="$3"
    local selected="$4"

    if [ "$selected" == "1" ]; then
        printf "%b> %-2d  %-40s %s %b\n" \
            "${BOLD}${MAGENTA}" "$index" "$label" "$status" "${NC}"
    else
        printf "  %-2d  %-40s %s\n" "$index" "$label" "$status"
    fi
}

check_step_done() {
    local step="$1"
    for done_step in "${STEPS_DONE[@]}"; do
        if [ "$done_step" == "$step" ]; then
            return 0
        fi
    done
    return 1
}

get_step_status() {
    local step="$1"
    if check_step_done "$step"; then
        printf "%b[OK]%b" "${GREEN}" "${NC}"
    else
        printf "%b[ ]%b" "${GRAY}" "${NC}"
    fi
}

########################################
# MENU DISPLAY AND NAVIGATION
########################################

display_main_menu() {
    MENU_OPTIONS=()
    TOTAL_MENU_ITEMS=0

    print_header
    
    printf "%b%s MAIN MENU%s\n" "${${NC}"BOLD}${ " "CYAN}" "
    print_separator
    
    MENU_OPTIONS[0]="System Check and Dependencies"
    MENU_OPTIONS[1]="Configure oFono (APN Settings)"
    MENU_OPTIONS[2]="Configure ConnMan"
    MENU_OPTIONS[3]="Configure LoRa Forwarder"
    MENU_OPTIONS[4]="Enable systemd Service"
    MENU_OPTIONS[5]="View Configuration Summary"
    MENU_OPTIONS[6]="System Reboot"
    MENU_OPTIONS[7]="Exit"
    
    TOTAL_MENU_ITEMS=8

    for i in "${!MENU_OPTIONS[@]}"; do
        local status=$(get_step_status "step_$i")
        local selected="0"
        [ "$i" -eq "$SELECTED_MENU" ] && selected="1"
        
        print_menu_item "$i" "${MENU_OPTIONS[$i]}" "$status" "$selected"
    done

    print_separator
    printf "%b[UP/DOWN] Navigate | [ENTER] Select | [Q] Exit%b\n" "${DIM}${CYAN}" "${NC}"
}

handle_menu_input() {
    local key
    read -rsn 1 key
    
    case "$key" in
        $'\033')
            read -rsn 2 key
            case "$key" in
                '[A')
                    SELECTED_MENU=$((SELECTED_MENU > 0 ? SELECTED_MENU - 1 : TOTAL_MENU_ITEMS - 1))
                    ;;
                '[B')
                    SELECTED_MENU=$(((SELECTED_MENU + 1) % TOTAL_MENU_ITEMS))
                    ;;
            esac
            ;;
        '')
            return 0
            ;;
        [Qq])
            return 2
            ;;
    esac
    return 1
}

########################################
# CONFIGURATION STEPS
########################################

step_check_system() {
    clear_screen
    print_header
    
    printf "%b%s SYSTEM CHECK%s\n" "${${NC}"BOLD}${ " "CYAN}" "
    print_separator
    
    log_info "Verifying system components and dependencies..."
    sleep 1
    
    local errors=0
    
    if [ -f "$OFONO_FILE" ]; then
        log_ok "oFono provisioning file: $OFONO_FILE"
    else
        log_warn "oFono provisioning file missing: $OFONO_FILE"
        ((errors++))
    fi
    
    if [ -f "$CONNMAN_FILE" ]; then
        log_ok "ConnMan configuration file: $CONNMAN_FILE"
    else
        log_warn "ConnMan configuration file missing: $CONNMAN_FILE"
        ((errors++))
    fi
    
    if command -v lorafwdctl &> /dev/null; then
        log_ok "lorafwdctl command available"
    else
        log_error "lorafwdctl command NOT found"
        ((errors++))
    fi
    
    if command -v systemctl &> /dev/null; then
        log_ok "systemctl command available"
    else
        log_error "systemctl command NOT found"
        ((errors++))
    fi
    
    print_separator
    
    if [ "$errors" -eq 0 ]; then
        log_ok "All checks passed. System is ready for configuration."
        STEPS_DONE+=("step_0")
    else
        log_error "Found $errors issues. Please contact system administrator."
    fi
    
    printf "\n%b" "${DIM}"
    read -p "Press ENTER to continue..."
    printf "%b" "${NC}"
}

step_config_ofono() {
    clear_screen
    print_header
    
    printf "%b%s oFONO CONFIGURATION (APN)%s\n" "${${NC}"BOLD}${ " "CYAN}" "
    print_separator
    
    log_info "Configuring mobile network settings (A1 Serbia - APN: internet)"
    print_separator
    
    if [ ! -f "$OFONO_FILE" ]; then
        log_error "oFono file not found: $OFONO_FILE"
        read -p "Press ENTER to continue..."
        return
    fi
    
    printf "%b" "${DIM}"
    read -p "Continue with configuration? (y/n) " -n 1 ans
    printf "%b\n" "${NC}"
    
    if [[ "${ans,,}" != "y" ]]; then
        log_warn "Operation cancelled"
        read -p "Press ENTER to continue..."
        return
    fi
    
    if grep -q "^\[operator:220,05\]" "$OFONO_FILE"; then
        log_ok "oFono block already configured"
    else
        log_info "Adding oFono operator block..."
        backup_file "$OFONO_FILE"
        
        cat >> "$OFONO_FILE" << 'EOF'

[operator:220,05]
internet.AccessPointName = internet
internet.Username = internet
internet.Password = internet
internet.AuthenticationMethod = chap
internet.Protocol = ip
EOF
        
        log_ok "oFono configuration updated successfully"
    fi
    
    STEPS_DONE+=("step_1")
    
    print_separator
    printf "%b" "${DIM}"
    read -p "Press ENTER to continue..."
    printf "%b" "${NC}"
}

step_config_connman() {
    clear_screen
    print_header
    
    printf "%b%s CONNMAN CONFIGURATION%s\n" "${${NC}"BOLD}${ " "CYAN}" "
    print_separator
    
    log_info "Configuring ConnMan network manager"
    print_separator
    
    if [ ! -f "$CONNMAN_FILE" ]; then
        log_error "ConnMan file not found: $CONNMAN_FILE"
        read -p "Press ENTER to continue..."
        return
    fi
    
    printf "%b" "${DIM}"
    read -p "Continue with configuration? (y/n) " -n 1 ans
    printf "%b\n" "${NC}"
    
    if [[ "${ans,,}" != "y" ]]; then
        log_warn "Operation cancelled"
        read -p "Press ENTER to continue..."
        return
    fi
    
    log_info "Updating ConnMan configuration..."
    backup_file "$CONNMAN_FILE"
    
    local VALUE="ethernet,wifi,cellular"
    
    if grep -q "^DefaultAutoConnectTechnologies=" "$CONNMAN_FILE"; then
        sed -i "s|^DefaultAutoConnectTechnologies=.*|DefaultAutoConnectTechnologies=$VALUE|" "$CONNMAN_FILE"
    else
        echo "DefaultAutoConnectTechnologies=$VALUE" >> "$CONNMAN_FILE"
    fi
    
    if grep -q "^PreferredTechnologies=" "$CONNMAN_FILE"; then
        sed -i "s|^PreferredTechnologies=.*|PreferredTechnologies=$VALUE|" "$CONNMAN_FILE"
    else
        echo "PreferredTechnologies=$VALUE" >> "$CONNMAN_FILE"
    fi
    
    log_ok "ConnMan configuration updated successfully"
    STEPS_DONE+=("step_2")
    
    print_separator
    printf "%b" "${DIM}"
    read -p "Press ENTER to continue..."
    printf "%b" "${NC}"
}

step_config_lora() {
    clear_screen
    print_header
    
    printf "%b%s LORA FORWARDER CONFIGURATION%s\n" "${${NC}"BOLD}${ " "CYAN}" "
    print_separator
    
    log_info "Configuring LoRa Forwarder settings"
    print_separator
    
    printf "%b" "${DIM}"
    read -p "Continue with configuration? (y/n) " -n 1 ans
    printf "%b\n" "${NC}"
    
    if [[ "${ans,,}" != "y" ]]; then
        log_warn "Operation cancelled"
        read -p "Press ENTER to continue..."
        return
    fi
    
    printf "\n%b" "${CYAN}"
    read -rp "Server address [89.216.124.213]: " SERVER
    SERVER=${SERVER:-89.216.124.213}
    printf "%b" "${NC}"
    
    printf "%b" "${CYAN}"
    read -rp "Uplink port [1700]: " UPLINK_PORT
    UPLINK_PORT=${UPLINK_PORT:-1700}
    printf "%b" "${NC}"
    
    printf "%b" "${CYAN}"
    read -rp "Downlink port [1700]: " DOWNLINK_PORT
    DOWNLINK_PORT=${DOWNLINK_PORT:-1700}
    printf "%b\n" "${NC}"
    
    log_info "Applying configuration via lorafwdctl..."
    
    if lorafwdctl -s gwmp.node "$SERVER" 2>/dev/null; then
        log_ok "Server set to: $SERVER"
    else
        log_warn "Error setting server address"
    fi
    
    if lorafwdctl gwmp.service.uplink "$UPLINK_PORT" 2>/dev/null; then
        log_ok "Uplink port set to: $UPLINK_PORT"
    else
        log_warn "Error setting uplink port"
    fi
    
    if lorafwdctl gwmp.service.downlink "$DOWNLINK_PORT" 2>/dev/null; then
        log_ok "Downlink port set to: $DOWNLINK_PORT"
    else
        log_warn "Error setting downlink port"
    fi
    
    STEPS_DONE+=("step_3")
    
    print_separator
    printf "%b" "${DIM}"
    read -p "Press ENTER to continue..."
    printf "%b" "${NC}"
}

step_systemd_service() {
    clear_screen
    print_header
    
    printf "%b%s SYSTEMD SERVICE MANAGEMENT%s\n" "${${NC}"BOLD}${ " "CYAN}" "
    print_separator
    
    log_info "Enabling and starting lorafwd service"
    print_separator
    
    printf "%b" "${DIM}"
    read -p "Continue? (y/n) " -n 1 ans
    printf "%b\n" "${NC}"
    
    if [[ "${ans,,}" != "y" ]]; then
        log_warn "Operation cancelled"
        read -p "Press ENTER to continue..."
        return
    fi
    
    log_info "Enabling service..."
    if systemctl enable --now lorafwd 2>/dev/null; then
        log_ok "Service successfully enabled and started"
    else
        log_error "Failed to start service"
    fi
    
    sleep 2
    
    log_info "Verifying service status..."
    if systemctl is-active --quiet lorafwd; then
        log_ok "Service status: ACTIVE"
    else
        log_warn "Service status: INACTIVE"
    fi
    
    STEPS_DONE+=("step_4")
    
    print_separator
    printf "%b" "${DIM}"
    read -p "Press ENTER to continue..."
    printf "%b" "${NC}"
}

step_preview_config() {
    clear_screen
    print_header
    
    printf "%b%s CONFIGURATION SUMMARY%s\n" "${${NC}"BOLD}${ " "CYAN}" "
    print_separator
    
    printf "%b[oFono Provisioning]%b\n" "${MAGENTA}" "${NC}"
    if [ -f "$OFONO_FILE" ]; then
        tail -10 "$OFONO_FILE" | sed 's/^/  /'
    else
        printf "  %bFile not found%b\n" "${RED}" "${NC}"
    fi
    
    print_separator
    
    printf "%b[ConnMan Configuration]%b\n" "${MAGENTA}" "${NC}"
    if [ -f "$CONNMAN_FILE" ]; then
        grep -E "(DefaultAutoConnect|PreferredTechnologies)" "$CONNMAN_FILE" | sed 's/^/  /'
    else
        printf "  %bFile not found%b\n" "${RED}" "${NC}"
    fi
    
    print_separator
    
    printf "%b[LoRaFwd Service Status]%b\n" "${MAGENTA}" "${NC}"
    if systemctl is-active --quiet lorafwd; then
        printf "  %bStatus: ACTIVE%b\n" "${GREEN}" "${NC}"
    else
        printf "  %bStatus: INACTIVE%b\n" "${RED}" "${NC}"
    fi
    
    print_separator
    printf "%b" "${DIM}"
    read -p "Press ENTER to continue..."
    printf "%b" "${NC}"
}

step_reboot() {
    clear_screen
    print_header
    
    printf "%b%s SYSTEM REBOOT%s\n" "${${NC}"BOLD}${ " "CYAN}" "
    print_separator
    
    log_warn "System reboot is recommended to apply all changes"
    print_separator
    
    printf "%b" "${DIM}"
    read -p "Reboot system now? (y/n) " -n 1 ans
    printf "%b\n" "${NC}"
    
    if [[ "${ans,,}" == "y" ]]; then
        log_warn "System rebooting in 5 seconds..."
        for i in {5..1}; do
            printf "%b  %d%b\n" "${YELLOW}" "$i" "${NC}"
            sleep 1
        done
        reboot
    else
        log_info "Reboot cancelled"
        read -p "Press ENTER to continue..."
    fi
}

########################################
# MAIN EVENT LOOP
########################################

main_loop() {
    while true; do
        display_main_menu
        
        while true; do
            handle_menu_input
            case $? in
                0) break ;;
                2) return ;;
            esac
            display_main_menu
        done
        
        case "$SELECTED_MENU" in
            0) step_check_system ;;
            1) step_config_ofono ;;
            2) step_config_connman ;;
            3) step_config_lora ;;
            4) step_systemd_service ;;
            5) step_preview_config ;;
            6) step_reboot ;;
            7) 
                clear_screen
\n"                printf "%b
                         Configuration Utility \n"Closed        printf "
%b\n\n" "${NC}"                printf "
                exit 0
                ;;
        esac
    done
}

main_loop