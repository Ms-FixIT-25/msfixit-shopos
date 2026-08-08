#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gui="$root/image/package/usr/share/msfixit-shopos/admin-console/public/hardware.php"
scanner="$root/image/package/usr/share/msfixit-shopos/admin-console/public/scanner-test.php"
scanner_lib="$root/image/package/usr/share/msfixit-shopos/admin-console/lib/scanner-validation.php"
nginx="$root/image/package/etc/nginx/snippets/msfixit-admin-console.conf"

php -l "$gui" >/dev/null
php -l "$scanner" >/dev/null
php -l "$scanner_lib" >/dev/null

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

grep -Fq "require_once '/usr/share/msfixit-shopos/admin-console/lib/scanner-validation.php'" "$scanner"
grep -Fq 'shoposEvaluateScannerInput' "$scanner"
grep -Fq 'Scandaten werden weder gespeichert noch protokolliert' "$scanner"
grep -Fq 'Enter = absenden, Tab = Fokus ins zweite Feld' "$scanner"
grep -Fq 'mindestens 50 Wiederholungen ohne verlorene Zeichen' "$scanner"
grep -Fq 'location = /admin/scanner-test {' "$nginx"
grep -Fq 'scanner-test.php' "$nginx"

# Peripheral rendering and scanner acceptance stay local/display-only: no shell,
# arbitrary device path or persistence of scanned payloads may be added here.
if grep -En '(shell_exec|exec\(|system\(|passthru\(|proc_open\()' "$gui" "$scanner" "$scanner_lib"; then
    echo 'Peripheral admin and scanner views must not execute shell commands.' >&2
    exit 1
fi
if grep -En '\$_(GET|POST|REQUEST).*?(device|path|queue|printer)' "$gui" "$scanner"; then
    echo 'Peripheral admin views must not execute user-selected device/queue paths.' >&2
    exit 1
fi
if grep -En '(file_put_contents|error_log|syslog|INSERT[[:space:]]+INTO|UPDATE[[:space:]].*scan)' "$scanner" "$scanner_lib"; then
    echo 'Scanner acceptance must not persist or log scanned payloads.' >&2
    exit 1
fi

printf 'PASS: Hardware Manager admin view and local scanner acceptance route expose conservative peripheral readiness without privileged device actions or scan persistence.\n'
