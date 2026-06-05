#!/usr/bin/env bash
set -uo pipefail

AUTO_MODE=0
if [ "${1:-}" == "-auto" ]; then
    AUTO_MODE=1
    shift
fi

if [ "$EUID" -ne 0 ]; then
    exec sudo -E bash "$0" ${AUTO_MODE:+-auto} "$@"
fi

readonly DEBUG_LOG="/tmp/tui_debug.log"
> "$DEBUG_LOG"

cleanup() {
    printf "%s" "$SHOW_CURSOR"
    stty echo
    stty sane
}
trap cleanup EXIT INT TERM


TUI_LINES=$(stty size | awk '{print $1}')
TUI_COLS=$(stty size | awk '{print $2}')

if [ "$TUI_COLS" -lt 80 ] || [ "$TUI_LINES" -lt 24 ]; then
    echo -e "\n\033[1;31m[!] Greška: Rezolucija terminala je premala ($TUI_COLS x $TUI_LINES).\033[0m"
    echo -e "Minimalni uslovi za ispravan TUI prikaz su \033[1;32m80 kolona i 24 linije\033[0m."
    echo -e "Molimo raširite Vaš prozor terminala i pokrenite skriptu ponovo.\n"
    exit 1
fi

readonly BOX_W=64
readonly BOX_H=16

readonly START_X=$(( (TUI_COLS - BOX_W) / 2 ))
readonly START_Y=$(( (TUI_LINES - BOX_H) / 2 ))

readonly OFONO_FILE="/etc/network/ofono/provisioning"
readonly CONNMAN_FILE="/etc/network/connman/main.conf"

STATUS_STEP_0=0
STATUS_STEP_1=0
STATUS_STEP_2=0
STATUS_STEP_3=0
STATUS_STEP_4=0

FINAL_APN="Nije podeseno"
FINAL_OPERATOR="Nepoznato"
FINAL_CONNMAN="Nije podeseno"
FINAL_LNS="Nije podeseno"
FINAL_PORTS="Nije podeseno"

FORM_APN="internet"
FORM_USER="internet"
FORM_PASS="internet"
FORM_MCCMNC="220,05"

LNS_SERVER="89.216.124.213"
UP_PORT="1700"
DOWN_PORT="1700"

readonly CLEAR_SCR=$'\033[2J'
readonly HIDE_CURSOR=$'\033[?25l'
readonly SHOW_CURSOR=$'\033[?25h'
readonly RESET=$'\033[0m'

if [ "$AUTO_MODE" -eq 1 ]; then
    readonly BG_COLOR=$'\033[46m' 
else
    readonly BG_COLOR=$'\033[44m' 
fi

readonly BOX_GRAY=$'\033[47m'
readonly TEXT_BLACK=$'\033[30m'
readonly TEXT_WHITE=$'\033[37m'
readonly SHADOW=$'\033[40m'
readonly BUTTON_ACT=$'\033[46;30m' 
readonly TEXT_GREEN=$'\033[32m'
readonly TEXT_RED=$'\033[31m'
readonly TEXT_GRAY=$'\033[90m'

move_cursor() {
    printf "\033[%d;%dH" "$1" "$2"
}

draw_background() {
    printf "%s" "$CLEAR_SCR"
    for ((i=1; i<=TUI_LINES; i++)); do
        move_cursor "$i" 1
        printf "%s%${TUI_COLS}s%s" "$BG_COLOR" "" "$RESET"
    done
}

draw_box() {
    for ((i=0; i<BOX_H; i++)); do
        move_cursor $((START_Y + i)) $START_X
        printf "%s%${BOX_W}s%s" "$BOX_GRAY" "" "$RESET"
    done
    for ((i=1; i<=BOX_H; i++)); do
        move_cursor $((START_Y + i)) $((START_X + BOX_W))
        printf "%s  %s" "$SHADOW" "$RESET"
    done
    move_cursor $((START_Y + BOX_H)) $((START_X + 2))
    printf "%s%${BOX_W}s%s" "$SHADOW" "" "$RESET"
}

print_in_box() {
    local row=$1
    local text=$2
    local align=${3:-"left"}
    local width=60 
    
    move_cursor $((START_Y + row)) $((START_X + 2))
    printf "%s%s" "$BOX_GRAY" "$TEXT_BLACK"
    
    local visible_len
    visible_len=$(echo -n "$text" | wc -m)
    
    if [ "$align" == "center" ]; then
        local spaces=$(( (width - visible_len) / 2 ))
        local extra_space=$(( (width - visible_len) % 2 ))
        printf "%*s%s%*s" $spaces "" "$text" $((spaces + extra_space)) ""
    else
        local padding=$(( width - visible_len - 1 ))
        printf " %s%*s" "$text" $padding ""
    fi
    printf "%s" "$RESET"
}

print_tui_title() {
    local title=$1
    local width=60
    local title_len
    title_len=$(echo -n "$title" | wc -m)
    
    local rem_dash=$(( width - 3 - 1 - title_len - 1 - 1 ))
    local dashes=""
    if [ $rem_dash -gt 0 ]; then
        printf -v dashes "%${rem_dash}s" ""
        dashes=${dashes// /─}
    fi
    
    move_cursor $((START_Y + 1)) $((START_X + 2))
    printf "%s%s┌── %s %s┐%s" "$BOX_GRAY" "$TEXT_BLACK" "$title" "$dashes" "$RESET"
}

draw_menu_item() {
    local row=$1
    local text=$2
    local is_selected=$3
    local width=60

    move_cursor $((START_Y + row)) $((START_X + 2))
    
    if [ "$is_selected" -eq 1 ]; then
        local item_str="  ➔ [ $text ]"
        local item_len
        item_len=$(echo -n "$item_str" | wc -m)
        local padding=$(( width - item_len ))
        printf "%s%s%*s%s" "$BUTTON_ACT" "$item_str" $padding "" "$RESET"
    else
        local item_str="     $text"
        local item_len
        item_len=$(echo -n "$item_str" | wc -m)
        local padding=$(( width - item_len ))
        printf "%s%s%s%*s%s" "$BOX_GRAY" "$TEXT_BLACK" "$item_str" $padding "" "$RESET"
    fi
}

draw_auto_screen() {
    draw_background
    draw_box
    print_tui_title "AUTOMATSKA KONFIGURACIJA"
    print_in_box 5 "Automatska konfiguracija u toku..." "center"
    print_in_box 6 "Molimo sačekajte." "center"
}

show_tui_spinner() {
    local -r bg_pid="$1"
    local -r action_text="$2"
    local -a spinner=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local idx=0
    local start_time; start_time=$(date +%s)

    printf "%s" "$HIDE_CURSOR"
    
    while kill -0 "$bg_pid" 2>/dev/null; do
        print_in_box 12 "[ ${spinner[$idx]} ] $action_text..." "center"
        idx=$(( (idx + 1) % 10 ))
        usleep 80000 2>/dev/null || sleep 0.1
    done
    wait "$bg_pid"
    local exit_code=$?

    local end_time; end_time=$(date +%s)
    local duration=$(( end_time - start_time ))
    if [ "$duration" -lt 1 ]; then
        for ((k=0; k<6; k++)); do
            print_in_box 12 "[ ${spinner[$idx]} ] $action_text..." "center"
            idx=$(( (idx + 1) % 10 ))
            usleep 80000 2>/dev/null || sleep 0.1
        done
    fi

    if [ $exit_code -ne 0 ]; then
        local last_err; last_err=$(tail -n 1 "$DEBUG_LOG" 2>/dev/null || echo "Nepoznata sistemska greška")
        [ -z "$last_err" ] && last_err="Komanda je vratila status greške $exit_code"
        
        print_in_box 11 "────────────────────────────────────────────────────────────"
        print_in_box 12 "GREŠKA: Izvršenje nije uspelo!" "center"
        print_in_box 13 "${TEXT_RED}${last_err:0:58}${RESET}" "center"
        
        if [ "$AUTO_MODE" -eq 1 ]; then
            echo "[!] Greška u auto modu preskočena nakon 3s: $last_err" >> "$DEBUG_LOG"
            sleep 3
            return 1
        else
            move_cursor $((START_Y + 14)) $((START_X + 17))
            printf "%s Pritisnite ENTER da preskocite grešku %s" "$BUTTON_ACT" "$RESET"
            read -r -s
            return 1
        fi
    fi
    return 0
}

show_tui_progress() {
    local -r bg_pid="$1"
    local -r text="$2"
    local -r max_timeout=15  
    local count=0
    local pct=0
    local bar=""

    printf "%s" "$HIDE_CURSOR"
    
    if [ "$AUTO_MODE" -eq 0 ]; then
        draw_background
        draw_box
        print_tui_title "DETEKCIJA HARDVERA"
        print_in_box 4 "$text" "center"
    fi

    while kill -0 "$bg_pid" 2>/dev/null && [ "$count" -lt "$((max_timeout * 10))" ]; do
        ((count++))
        if [ $pct -lt 85 ]; then pct=$(( pct + 5 )); elif [ $pct -lt 98 ]; then pct=$(( pct + 1 )); fi

        local num_blocks=$(( pct / 5 ))
        bar=""
        for ((j=1; j<=20; j++)); do
            [ $j -le $num_blocks ] && bar="${bar}█" || bar="${bar}░"
        done

        local target_row=7
        [ "$AUTO_MODE" -eq 1 ] && target_row=9

        print_in_box $target_row "Status: [$bar] $pct%" "center"
        usleep 100000 2>/dev/null || sleep 0.1
    done
    wait "$bg_pid"

    local target_row=7
    [ "$AUTO_MODE" -eq 1 ] && target_row=9

    print_in_box $target_row "Status: [████████████████████] 100%" "center"
    sleep 0.5
    
    if [ "$AUTO_MODE" -eq 1 ]; then
        print_in_box 9 "" "center"
    fi
}

ui_menu() {
    local title=$1
    local prompt=$2
    local current=0
    local prev=0
    local options=("A1 Srbija" "MTS Srbija (Telekom)" "Yettel Srbija" "Rucni unos")
    
    printf "%s" "$HIDE_CURSOR"
    stty -echo
    
    draw_background
    draw_box
    print_tui_title "$title"
    print_in_box 3 "$prompt" "center"
    print_in_box 11 "────────────────────────────────────────────────────────────"
    print_in_box 13 "[ Koristite STRELICE za kretanje, ENTER za potvrdu ]" "center"
    
    for i in "${!options[@]}"; do
        if [ $i -eq $current ]; then
            draw_menu_item $((5 + i)) "${options[$i]}" 1
        else
            draw_menu_item $((5 + i)) "${options[$i]}" 0
        fi
    done
    
    while true; do
        read -r -s -n 1 key
        if [[ $key == $'\x1b' ]]; then
            read -r -s -n 2 key
            prev=$current
            if [[ $key == "[A" ]]; then
                ((current--))
                [ $current -lt 0 ] && current=3
            elif [[ $key == "[B" ]]; then
                ((current++))
                [ $current -gt 3 ] && current=0
            fi
            
            if [ $current -ne $prev ]; then
                draw_menu_item $((5 + prev)) "${options[$prev]}" 0
                draw_menu_item $((5 + current)) "${options[$current]}" 1
            fi
        elif [[ $key == "" ]]; then
            break
        fi
    done
    
    stty echo
    printf "%s" "$SHOW_CURSOR"
    return $current
}

edit_form_row() {
    local row=$1
    local var_name=$2
    local current_val="${!var_name}"
    local user_input=""

    while true; do
        move_cursor $((START_Y + row)) $((START_X + 24))
        if [ -z "$user_input" ]; then
            printf "%s%s%-30s%s" "$BOX_GRAY" "$TEXT_GRAY" "($current_val)" "$RESET"
            move_cursor $((START_Y + row)) $((START_X + 24))
        else
            printf "%s%s%-30s%s" "$BOX_GRAY" "$TEXT_BLACK" "$user_input" "$RESET"
            move_cursor $((START_Y + row)) $((START_X + 24 + ${#user_input}))
        fi

        local char=""
        if ! read -r -s -n 1 char; then
            break
        fi

        if [[ "$char" == "" || "$char" == $'\x0a' || "$char" == $'\x0d' ]]; then
            break
        fi

        if [[ "$char" == $'\x7f' || "$char" == $'\x08' ]]; then
            if [ ${#user_input} -gt 0 ]; then
                user_input="${user_input%?}"
                move_cursor $((START_Y + row)) $((START_X + 24))
                printf "%s%s%-30s%s" "$BOX_GRAY" "$TEXT_BLACK" "$user_input" "$RESET"
            fi
        else
            if [[ ${#char} -eq 1 && "$char" =~ [[:print:]] ]]; then
                if [ ${#user_input} -lt 30 ]; then
                    user_input="${user_input}${char}"
                fi
            fi
        fi
    done

    user_input=$(echo "$user_input" | xargs)
    if [ -n "$user_input" ]; then
        eval "$var_name=\"\$user_input\""
    fi

    move_cursor $((START_Y + row)) $((START_X + 24))
    printf "%s%30s%s" "$BOX_GRAY" "" "$RESET"
    
    move_cursor $((START_Y + row)) $((START_X + 24))
    printf "%s%s%-30s%s" "$BOX_GRAY" "$TEXT_BLACK" "${!var_name}" "$RESET"
}

ui_ofono_form() {
    stty -echo
    printf "%s" "$SHOW_CURSOR"

    draw_background
    draw_box
    print_tui_title "KORAK 2: SELEKCIJA APN - RUČNI UNOS"
    print_in_box 3 "Unesite parametre (ENTER za prelazak na sledeće polje):" "center"

    draw_skeleton() {
        local r=$1; local lbl=$2; local v=$3
        move_cursor $((START_Y + r)) $((START_X + 4))
        printf "%s%s%-18s[ %-30s ]%s" "$BOX_GRAY" "$TEXT_BLACK" "$lbl" "$v" "$RESET"
    }

    draw_skeleton 5  "APN Endpoint:"   "$FORM_APN"
    draw_skeleton 7  "Korisničko ime:" "$FORM_USER"
    draw_skeleton 9  "Lozinka:"        "$FORM_PASS"
    draw_skeleton 11 "MCC,MNC Kod:"    "$FORM_MCCMNC"

    edit_form_row 5  "FORM_APN"
    edit_form_row 7  "FORM_USER"
    edit_form_row 9  "FORM_PASS"
    edit_form_row 11 "FORM_MCCMNC"

    stty echo
    printf "%s" "$HIDE_CURSOR"
}

ui_lora_form() {
    stty -echo
    printf "%s" "$SHOW_CURSOR"

    draw_background
    draw_box
    print_tui_title "KORAK 4: FORMA ZA LNS RUTIRANJE"
    print_in_box 3 "Unesite mrežne parametre LNS servera:" "center"

    draw_skeleton() {
        local r=$1; local lbl=$2; local v=$3
        move_cursor $((START_Y + r)) $((START_X + 4))
        printf "%s%s%-18s[ %-30s ]%s" "$BOX_GRAY" "$TEXT_BLACK" "$lbl" "$v" "$RESET"
    }

    draw_skeleton 6 "LNS Server IP:" "$LNS_SERVER"
    draw_skeleton 8 "Uplink Port:"   "$UP_PORT"
    draw_skeleton 10 "Downlink Port:" "$DOWN_PORT"

    edit_form_row 6  "LNS_SERVER"
    edit_form_row 8  "UP_PORT"
    edit_form_row 10 "DOWN_PORT"

    stty echo
    printf "%s" "$HIDE_CURSOR"
}

ui_msgbox() {
    local title=$1
    local text1=$2
    local text2=$3
    local text3=${4:-""}
    
    printf "%s" "$HIDE_CURSOR"
    draw_background
    draw_box
    print_tui_title "$title"
    print_in_box 4 "$text1" "center"
    print_in_box 6 "$text2" "center"
    [ -n "$text3" ] && print_in_box 8 "$text3" "center"
    
    move_cursor $((START_Y + 12)) $((START_X + 17))
    printf "%s Pritisnite ENTER za nastavak %s" "$BUTTON_ACT" "$RESET"
    
    read -r -s
}

ui_yesno() {
    local title=$1
    local text1=$2
    local text2=$3
    local current=0 
    
    stty -echo
    printf "%s" "$HIDE_CURSOR"
    
    draw_background
    draw_box
    print_tui_title "$title"
    print_in_box 5 "$text1" "center"
    print_in_box 7 "$text2" "center"
    
    while true; do
        if [ $current -eq 0 ]; then
            move_cursor $((START_Y + 12)) $((START_X + 18))
            printf "%s  < DA >  %s      < NE >  " "$BUTTON_ACT" "$RESET"
        else
            move_cursor $((START_Y + 12)) $((START_X + 18))
            printf "  < DA >        %s  < NE >  %s" "$BUTTON_ACT" "$RESET"
        fi
        
        read -r -s -n 1 key
        if [[ $key == $'\x1b' ]]; then
            read -r -s -n 2 key
            if [[ $key == "[D" || $key == "[C" ]]; then 
                [ $current -eq 0 ] && current=1 || current=0
            fi
        elif [[ $key == "" ]]; then
            break
        fi
    done
    stty echo
    printf "%s" "$SHOW_CURSOR"
    return $current
}

backup_file() {
    local f="$1"
    if [ -f "$f" ]; then
        cp "$f" "${f}.bak" 2>>"$DEBUG_LOG"
    fi
}

step_check_system() {
    local errors=""
    local err_cnt=0

    [ ! -f "$OFONO_FILE" ] && { errors="${errors}• oFono datoteka nedostaje\n"; ((err_cnt++)); }
    [ ! -f "$CONNMAN_FILE" ] && { errors="${errors}• ConnMan datoteka nedostaje\n"; ((err_cnt++)); }
    ! command -v lorafwdctl &>/dev/null && { errors="${errors}• Alat lorafwdctl nije mapiran\n"; ((err_cnt++)); }
    ! command -v systemctl &>/dev/null && { errors="${errors}• Systemctl nije pronadjen\n"; ((err_cnt++)); }

    if [ $err_cnt -eq 0 ]; then
        STATUS_STEP_0=1
        if [ "$AUTO_MODE" -eq 0 ]; then
            ui_msgbox "KORAK 1: VERIFIKACIJA" "Provera sistemskih fajlova..." "Sistem ispunjava sve tehničke preduslove!"
        fi
    else
        if [ "$AUTO_MODE" -eq 1 ]; then
            echo "[!] Kritične anomalije preskočene u auto modu: $errors" >> "$DEBUG_LOG"
            STATUS_STEP_0=0
        else
            if ! ui_yesno "UPOZORENJE !" "Detektovane anomalije ($err_cnt):" "$errors Da li želite nastavak?"; then
                exit 1
            fi
        fi
    fi
}

step_config_ofono() {
    local DETECTED="nepoznat"

    detect_cops() {
        local port="$1"
        local tmp_file="/tmp/cops_res.tmp"
        > "$tmp_file"
        ( cat "$port" > "$tmp_file" 2>/dev/null ) &
        local cat_pid=$!
        sleep 0.2
        echo -e "AT\r" > "$port" 2>/dev/null
        sleep 0.2
        echo -e "AT+COPS?\r" > "$port" 2>/dev/null
        sleep 1.2
        kill "$cat_pid" 2>/dev/null || true
        wait "$cat_pid" 2>/dev/null || true
        cat "$tmp_file" 2>/dev/null || true
        rm -f "$tmp_file"
    }

    run_detection_in_bg() {
        if ls /dev/ttyUSB* >/dev/null 2>&1; then
            for p in /dev/ttyUSB*; do
                local res; res=$(detect_cops "$p")
                local det; det=$(echo "$res" | grep -oE '"[^"]+"' | head -n1 | tr -d '"')
                if [[ -n "$det" ]]; then echo "$det"; return 0; fi
            done
        fi
        if command -v mmcli &>/dev/null; then
            local det; det=$(mmcli -m 0 2>/dev/null | awk -F: '/operator name/ {gsub(/ /,"",$2); print $2}' || true)
            if [[ -n "$det" ]]; then echo "$det"; return 0; fi
        fi
        echo "nepoznat"
    }

    run_detection_in_bg > /tmp/detected_operator.tmp 2>>"$DEBUG_LOG" &
    local detect_pid=$!
    
    show_tui_progress "$detect_pid" "Inicijalizacija modema i skeniranje operatera..."

    DETECTED=$(cat /tmp/detected_operator.tmp 2>/dev/null || echo "nepoznat")
    rm -f /tmp/detected_operator.tmp
    FINAL_OPERATOR="$DETECTED"

    local MCCMNC APN USER PASS
    local auto_profile=0

    if [ "$AUTO_MODE" -eq 1 ]; then
        case "$DETECTED" in
            *A1*|*SRB*)          MCCMNC="220,05" ; APN="internet" ; USER="internet" ; PASS="internet" ; auto_profile=1 ;;
            *MTS*|*TELEKOM*)    MCCMNC="220,03" ; APN="3ginternet" ; USER="mts" ; PASS="064" ; auto_profile=1 ;;
            *YETTEL*)           MCCMNC="220,01" ; APN="internet" ; USER="yettel" ; PASS="gprs" ; auto_profile=1 ;;
            *)
                ui_ofono_form
                APN="$FORM_APN"
                USER="$FORM_USER"
                PASS="$FORM_PASS"
                MCCMNC="$FORM_MCCMNC"
                auto_profile=0
                draw_auto_screen
                ;;
        esac
    else
        if ui_yesno "KORAK 2: MOBILNA MREŽA" "Detektovan operater: $DETECTED" "Da li želite automatsko generisanje profila?"; then
            auto_profile=1
        fi

        if [ "$auto_profile" -eq 1 ]; then
            case "$DETECTED" in
                *A1*|*SRB*)          MCCMNC="220,05" ; APN="internet" ; USER="internet" ; PASS="internet" ;;
                *MTS*|*TELEKOM*)    MCCMNC="220,03" ; APN="3ginternet" ; USER="mts" ; PASS="064" ;;
                *YETTEL*)           MCCMNC="220,01" ; APN="internet" ; USER="yettel" ; PASS="gprs" ;;
                *)
                    ui_msgbox "PROFIL NIJE PRONAĐEN" "Operater '$DETECTED' je nepoznat." "Potreban je ručni unos podataka."
                    auto_profile=0
                    ;;
            esac
        fi

        if [ "$auto_profile" -eq 0 ]; then
            ui_menu "KORAK 2: SELEKCIJA APN" "Izaberite profil mobilnog operatera iz baze:"
            local op_choice=$?
            case "$op_choice" in
                0) MCCMNC="220,05"; APN="internet"; USER="internet"; PASS="internet" ;;
                1) MCCMNC="220,03"; APN="3ginternet"; USER="mts"; PASS="064" ;;
                2) MCCMNC="220,01"; APN="internet"; USER="yettel"; PASS="gprs" ;;
                3)
                    ui_ofono_form
                    APN="$FORM_APN"
                    USER="$FORM_USER"
                    PASS="$FORM_PASS"
                    MCCMNC="$FORM_MCCMNC"
                    ;;
            esac
        fi
    fi

    if [ ! -f "$OFONO_FILE" ]; then return; fi
    backup_file "$OFONO_FILE"
    FINAL_APN="$APN"

    write_ofono_bg() {
        local BLOCK="[operator:${MCCMNC}]
internet.AccessPointName = ${APN}
internet.Username = ${USER}
internet.Password = ${PASS}
internet.AuthenticationMethod = chap
internet.Protocol = ip"

        if grep -q "^\[operator:${MCCMNC}\]" "$OFONO_FILE"; then
            awk -v op="operator:${MCCMNC}" -v block="$BLOCK" '$0 ~ "\\["op"\\]" {skip=1; print block; next} /^\[/ && skip {skip=0} !skip' "$OFONO_FILE" > "${OFONO_FILE}.tmp" && mv "${OFONO_FILE}.tmp" "$OFONO_FILE"
        else
            printf "\n%s\n" "$BLOCK" >> "$OFONO_FILE"
        fi
    } 2>>"$DEBUG_LOG"
    
    if [ "$AUTO_MODE" -eq 0 ]; then
        draw_background; draw_box
        print_tui_title "KORAK 2: SNIMANJE"
        print_in_box 5 "Sinhronizacija oFono mrežne konfiguracije..." "center"
    fi
    
    write_ofono_bg &
    if show_tui_spinner "$!" "Zapisivanje na memoriju"; then
        STATUS_STEP_1=1
    fi
    sleep 3
}

step_config_connman() {
    if [ ! -f "$CONNMAN_FILE" ]; then return; fi

    local run_step=0
    if [ "$AUTO_MODE" -eq 1 ]; then
        run_step=1
    else
        if ui_yesno "KORAK 3: MREŽNI PRIORITETI" "Konfigurisati mrežne prioritete?" "Redosled: Ethernet -> Wi-Fi -> Cellular Failover"; then
            run_step=1
        fi
    fi

    if [ "$run_step" -eq 1 ]; then
        write_connman_bg() {
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
        } 2>>"$DEBUG_LOG"

        FINAL_CONNMAN="ethernet,wifi,cellular"
        
        if [ "$AUTO_MODE" -eq 0 ]; then
            draw_background; draw_box
            print_tui_title "KORAK 3: SNIMANJE"
            print_in_box 5 "Ažuriranje mrežnih prioriteta unutar ConnMan-a..." "center"
        fi
        
        write_connman_bg &
        if show_tui_spinner "$!" "Rekonfiguracija rutera"; then
            STATUS_STEP_2=1
        fi
    fi
    sleep 3
}

step_config_lora() {
    if [ "$AUTO_MODE" -eq 0 ]; then
        if ui_yesno "KORAK 4: LNS RUTIRANJE" "Podrazumevani server: $LNS_SERVER (DNW server)" "Da li želite da zadržite podrazumevane parametre?"; then
            :
        else
            ui_lora_form
        fi
    fi

    FINAL_LNS="$LNS_SERVER"
    FINAL_PORTS="Up: ${UP_PORT} / Down: ${DOWN_PORT}"

    apply_lora_bg() {
        lorafwdctl -s gwmp.node "$LNS_SERVER" 2>>"$DEBUG_LOG" || return 1
        lorafwdctl gwmp.service.uplink "$UP_PORT" 2>>"$DEBUG_LOG" || return 2
        lorafwdctl gwmp.service.downlink "$DOWN_PORT" 2>>"$DEBUG_LOG" || return 3
    }

    if [ "$AUTO_MODE" -eq 0 ]; then
        draw_background; draw_box
        print_tui_title "KORAK 4: LNS PROVIZIONISANJE"
        print_in_box 5 "Inicijalizacija konekcije ka mrežnom serveru..." "center"
    fi
    
    apply_lora_bg &
    if show_tui_spinner "$!" "Uspostavljanje UDP veze ka LNS-u..."; then
        STATUS_STEP_3=1
    fi
}

step_systemd_service() {
    local run_step=0
    if [ "$AUTO_MODE" -eq 1 ]; then
        run_step=1
    else
        if ui_yesno "KORAK 5: AUTOMATIZACIJA" "Registrovati 'lorafwd' servis?" "Podrazumeva automatsko podizanje procesa pri boot-u"; then
            run_step=1
        fi
    fi

    if [ "$run_step" -eq 1 ]; then
        systemd_bg() {
            systemctl daemon-reload 2>>"$DEBUG_LOG" || return 1
            systemctl enable --now lorafwd 2>>"$DEBUG_LOG" || return 2
        }

        if [ "$AUTO_MODE" -eq 0 ]; then
            draw_background; draw_box
            print_tui_title "KORAK 5: SYSTEMD"
            print_in_box 5 "Registracija lorafwd u sistemsku start-up sekvencu..." "center"
        fi
        
        systemd_bg &
        if show_tui_spinner "$!" "Povezivanje pozadinskih procesa"; then
            systemctl is-active lorafwd &>/dev/null && STATUS_STEP_4=1
        fi
    fi
}

show_wizard_summary() {
    printf "%s" "$HIDE_CURSOR"
    stty -echo

    local eui="Nepoznato"
    if [ -f "/var/run/boardinfo.env" ]; then
        eui=$(grep "EUI64" /var/run/boardinfo.env | cut -d'=' -f2 | tr -d '"')
    fi

    draw_background
    draw_box
    
    print_tui_title "PREGLED PODEŠAVANJA"
    
    local s0; [ $STATUS_STEP_0 -eq 1 ] && s0="OK" || s0="--"
    local s1; [ $STATUS_STEP_1 -eq 1 ] && s1="OK" || s1="--"
    local s2; [ $STATUS_STEP_2 -eq 1 ] && s2="OK" || s2="--"
    local s3; [ $STATUS_STEP_3 -eq 1 ] && s3="OK" || s3="--"
    local s4; [ $STATUS_STEP_4 -eq 1 ] && s4="OK" || s4="--"

    print_in_box 3 "Hardver [$s0] | oFono [$s1] | ConnMan [$s2] | LNS [$s3]" "center"
    print_in_box 4 "────────────────────────────────────────────────────────────"
    
    print_in_box 6 " • Gateway EUI:       $eui"
    print_in_box 7 " • Mobilni operater:  $FINAL_OPERATOR"
    print_in_box 8 " • Primenjen APN:     $FINAL_APN"
    print_in_box 9 " • LNS Server IP:     $FINAL_LNS"
    print_in_box 10 " • LoRa UDP Portovi:  $FINAL_PORTS"
    
    local svc_status="OFFLINE"
    systemctl is-active lorafwd &>/dev/null && svc_status="ONLINE"
    print_in_box 11 " • Status servisa:    $svc_status"
    print_in_box 12 "────────────────────────────────────────────────────────────"

    if [ "$AUTO_MODE" -eq 1 ]; then
        for ((i=10; i>=1; i--)); do
            print_in_box 14 "[ Automatski restart za ${i}s... ]" "center"
            sleep 1
        done
        printf "%s" "$CLEAR_SCR"
        move_cursor 1 1
        echo "Sistem se restartuje automatski..."
        sleep 0.5
        reboot
    else
        move_cursor $((START_Y + 14)) $((START_X + 17))
        printf "%s Pritisnite ENTER za nastavak %s" "$BUTTON_ACT" "$RESET"

        while true; do
            read -r -s -n 1 key
            if [[ "$key" == "" || "$key" == $'\x0a' || "$key" == $'\x0d' ]]; then
                break
            fi
        done

        if ui_yesno "KONFIGURACIJA ZAVRŠENA" "Izmene zahtevaju ponovno pokretanje uređaja." "Da li želite da restartujete gateway odmah?"; then
            printf "%s" "$CLEAR_SCR"
            move_cursor 1 1
            echo "Sistem će se uskoro restartovati..."
            sleep 0.5
            echo -e "\nAko do sada niste kopirali Gateway EUI, sada je vreme da to učinite: \033[0;32m\t\t\t$eui\033[0m"
            sleep 5
            reboot
        else
            printf "%s" "$CLEAR_SCR"
            move_cursor 1 1
            echo -e "\033[0;32m[✔]\033[0m Konfiguracija uspešno sinhronizovana. EUI: $eui\n"
        fi
    fi
}

run_wizard() {
    if [ "$AUTO_MODE" -eq 1 ]; then
        draw_auto_screen
    fi
    step_check_system
    step_config_ofono
    step_config_connman
    step_config_lora
    step_systemd_service
    show_wizard_summary
}

run_wizard