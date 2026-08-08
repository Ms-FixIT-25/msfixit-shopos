#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gui="$root/image/package/usr/share/msfixit-shopos/admin-console/public/hardware.php"

php -l "$gui" >/dev/null

grep -Fq 'function peripheralLabel(string $kind):string' "$gui"
grep -Fq 'function peripheralReadiness(array $device,int $printerCount):array' "$gui"
grep -Fq "'barcode_scanner'=>'Barcode-Scanner'" "$gui"
grep -Fq "'receipt_printer'=>'Bondrucker'" "$gui"
grep -Fq "'label_printer'=>'Etikettendrucker'" "$gui"
grep -Fq "'a4_printer'=>'A4-Drucker'" "$gui"
grep -Fq "['Bereit','success','Barcode-Eingabe erkannt; physischer Scan-Test bleibt erforderlich']" "$gui"
grep -Fq "['Zuordnung prüfen','warning','CUPS-Queue vorhanden; eindeutige Zuordnung und Testdruck erforderlich']" "$gui"
grep -Fq 'USB-Geräte aktuell verbunden' "$gui"
grep -Fq 'die Seite aktualisiert sich alle 15 Sekunden' "$gui"
grep -Fq 'Bereit“ bestätigt Software-/Treiberfähigkeit, ersetzt aber keinen physischen Abnahmetest' "$gui"
grep -Fq "capabilityLabel((string)\$cap)" "$gui"

# Peripheral rendering must remain display-only: no device path, shell command or
# arbitrary CUPS queue creation may be accepted from request parameters here.
if grep -En '(shell_exec|exec\(|system\(|passthru\(|proc_open\()' "$gui"; then
    echo 'Peripheral admin view must not execute shell commands.' >&2
    exit 1
fi
if grep -En '\$_(GET|POST|REQUEST).*?(device|path|queue|printer)' "$gui"; then
    echo 'Peripheral admin view must not execute user-selected device/queue paths.' >&2
    exit 1
fi

printf 'PASS: Hardware Manager admin view exposes semantic peripheral readiness without claiming physical approval or adding privileged device actions.\n'
