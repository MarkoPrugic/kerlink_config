# Kerlink Gateway Configuration Script 🚀

![Platform](https://img.shields.io/badge/Platform-Kerlink%20keros-blue)
![LoRaWAN](https://img.shields.io/badge/LoRaWAN-Gateway-success)
![Shell](https://img.shields.io/badge/Shell-Bash-orange)
![Status](https://img.shields.io/badge/Status-Active-success)
![License](https://img.shields.io/badge/License-MIT-green)

Interaktivna Bash TUI skripta za automatsku ili ručnu konfiguraciju Kerlink LoRaWAN gateway uređaja.

Skripta vodi korisnika kroz proces konfiguracije mobilne mreže, mrežnog menadžmenta i povezivanja gateway-a sa željenim LoRaWAN Network Server (LNS) okruženjem.

---

## 🚀 Brzi početak

Preuzimanje i pokretanje skripte u jednom koraku:

```bash id="zk4gfd"
wget -O configure.sh https://raw.githubusercontent.com/MarkoPrugic/kerlink_config/main/configure.sh && sudo bash configure.sh
```
#### AUTOMATSKI MOD

```bash id="zk4gfd"
wget -O configure.sh https://raw.githubusercontent.com/MarkoPrugic/kerlink_config/main/configure.sh && sudo bash configure.sh -auto
```

---

## ✨ Karakteristike

* Automatsko čišćenje terminala pri pokretanju
* Automatska provera root privilegija
* Kreiranje rezervnih kopija konfiguracionih fajlova
* Konfiguracija mobilne mreže (oFono)
* Konfiguracija ConnMan mrežnog menadžera
* Interaktivna konfiguracija LoRa Forwarder-a
* Automatsko pokretanje i omogućavanje systemd servisa
* Jednostavno korišćenje bez ručnog editovanja konfiguracionih fajlova

---

## 📁 Struktura repozitorijuma

```text id="efh2pu"
kerlink_config/
├── README.md
└── config.sh
```

---

## 🛠 Funkcionalnosti

### 🔐 Automatska provera privilegija

* Provera da li je skripta pokrenuta kao root korisnik
* Automatsko ponovno pokretanje korišćenjem `sudo` ukoliko je potrebno

### 📡 oFono Provisioning konfiguracija

* Provera postojanja provisioning fajla
* Kreiranje rezervne kopije (`.bak`)
* Dodavanje ili ažuriranje APN konfiguracije
* Sprečavanje dupliranja postojećih unosa

### 🌐 ConnMan konfiguracija

* Automatsko ažuriranje `/etc/connman/main.conf`
* Podešavanje prioriteta mrežnih interfejsa:

```text id="ytfr3v"
PreferredTechnologies=ethernet,wifi,cellular
```

### 📶 LoRa Forwarder konfiguracija

Interaktivni unos:

* LNS adrese
* Uplink porta
* Downlink porta

Primena konfiguracije pomoću:

```bash id="8txkcl"
lorafwdctl
```

Nakon toga skripta:

* Omogućava `lorafwd` servis
* Pokreće servis
* Proverava status servisa

### 🔄 Restart sistema

* Opcioni restart po završetku konfiguracije

---

## 📋 Preduslovi

* Kerlink gateway sa KerOS 6 operativnim sistemom
* SSH ili serijski pristup uređaju
* Aktivna mrežna konekcija
* Root ili sudo privilegije

---

## 🧪 Testirani uređaji

* Kerlink Wirnet iStation
* Kerlink iFemtoCell

Skripta bi trebalo da funkcioniše i na drugim Kerlink uređajima zasnovanim na KerOS 6 platformi.

---

## 📄 Licenca

Ovaj projekat je licenciran pod MIT licencom.

---

## 👨‍💻 Autor

Marko Prugić

GitHub: https://github.com/MarkoPrugic
