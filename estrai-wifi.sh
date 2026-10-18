#!/usr/bin/env bash
# Crea wifi.env (solo-utente) con SSID e password della rete Wi-Fi a cui
# questo PC è connesso adesso, senza stamparli a schermo.
set -euo pipefail
cd "$(dirname "$0")"

N=nmcli
command -v nmcli >/dev/null || N="distrobox-host-exec nmcli"

CON=$($N -t -f NAME,TYPE connection show --active | awk -F: '$2=="802-11-wireless"{print $1; exit}')
[ -n "$CON" ] || { echo "Nessuna connessione Wi-Fi attiva" >&2; exit 1; }

SSID=$($N -g 802-11-wireless.ssid connection show "$CON")
PSK=$($N -s -g 802-11-wireless-security.psk connection show "$CON")
[ -n "$PSK" ] || { echo "Password non leggibile (salvata nel portachiavi?)" >&2; exit 1; }

umask 077
printf 'WIFI_SSID="%s"\nWIFI_PSK="%s"\n' "$SSID" "$PSK" > wifi.env
echo "wifi.env creato per la rete \"$SSID\""
