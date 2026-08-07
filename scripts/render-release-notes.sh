#!/usr/bin/env bash
set -Eeuo pipefail

version="${1:?usage: render-release-notes.sh VERSION}"
semver_re='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
[[ "$version" =~ $semver_re ]] || {
    echo "Invalid ShopOS release version: $version" >&2
    exit 2
}

base="msfixit-shopos-${version}-rpi4-usb"
desktop="${base}-windows-macos.zip"
desktop_sha="${desktop}.sha256"
linux="${base}-linux.img.xz"
linux_sha="${linux}.sha256"
layout="${base}.ab-layout"
version_file="SHOPOS-${version}-VERSION.txt"
extracted="${base}.img"

template="$(mktemp)"
trap 'rm -f "$template"' EXIT

cat > "$template" <<'EOF'
## ShopOS @VERSION@ einmal installieren – danach über das Update Center warten

Dieses Release enthält das vollständige, startfähige ShopOS-Image für einen Raspberry Pi 4 Model B. Das Image wird einmalig auf eine SD-Karte oder vorzugsweise eine USB-SSD geschrieben. Normale spätere ShopOS- und App-Aktualisierungen erfolgen anschließend direkt im lokalen **ShopOS Control Center**.

### Welcher Download ist richtig?

| Betriebssystem | Empfohlene Datei | Verwendung |
|---|---|---|
| Windows 10/11 | `@DESKTOP@` | ZIP vollständig entpacken und die enthaltene `@EXTRACTED@` mit Raspberry Pi Imager schreiben |
| macOS | `@DESKTOP@` | ZIP im Finder vollständig entpacken und die enthaltene `@EXTRACTED@` mit Raspberry Pi Imager schreiben |
| Linux | `@LINUX@` | Direkt mit Raspberry Pi Imager verwenden oder zuerst mit `xz` entpacken |

Das gemeinsame Windows/macOS-ZIP ist eindeutig als Desktop-Paket bezeichnet. Ein zweites, inhaltlich identisches Gigabyte-Paket nur mit anderem macOS-Namen wird bewusst nicht erzeugt. Das enthaltene Image ist vollständig materialisiert und besitzt nach dem Entpacken keine Sparse-Lücken, damit Raspberry Pi Imager den Schreibfortschritt korrekt von 0 bis 100 Prozent anzeigen kann.

### Installation unter Windows

1. `@DESKTOP@` und `@DESKTOP_SHA@` herunterladen.
2. Das ZIP über **Alle extrahieren** vollständig entpacken.
3. Die IMG-Datei nicht direkt aus 7-Zip, WinRAR oder dem ZIP-Ordner öffnen.
4. Raspberry Pi Imager starten und **Eigenes Image verwenden** auswählen.
5. `@EXTRACTED@` und anschließend das richtige Zielmedium auswählen.
6. Schreiben und Verifizieren vollständig abschließen lassen.

### Installation unter macOS

1. `@DESKTOP@` und `@DESKTOP_SHA@` herunterladen.
2. Das ZIP per Doppelklick im Finder vollständig entpacken.
3. Raspberry Pi Imager starten und **Use custom** beziehungsweise **Eigenes Image verwenden** auswählen.
4. `@EXTRACTED@` und anschließend das richtige Zielmedium auswählen.
5. Das angeforderte Administratorkennwort bestätigen und die Verifikation vollständig abwarten.

### Installation unter Linux

1. `@LINUX@` und `@LINUX_SHA@` herunterladen.
2. Die Prüfsumme kontrollieren.
3. Das XZ-Image direkt mit Raspberry Pi Imager verwenden oder zuerst entpacken.
4. Schreiben und Verifizieren vollständig abschließen lassen.

### Enthaltene Downloads

- `@DESKTOP@` – Desktop-Paket für Windows und macOS
- `@DESKTOP_SHA@` – SHA-256-Prüfsumme des Desktop-Pakets
- `@LINUX@` – kompaktes XZ-Image für Linux und fortgeschrittene Nutzung
- `@LINUX_SHA@` – SHA-256-Prüfsumme des XZ-Images
- `@LAYOUT@` – dokumentiertes A/B-Partitionslayout
- `@VERSION_FILE@` – maschinenlesbare ShopOS-Version

### Aktualisierung ohne erneutes Flashen

ShopOS besitzt zwei getrennte Root-Systembereiche. Ein Systemupdate wird ausschließlich in den inaktiven Bereich geschrieben, vollständig geprüft und beim nächsten Neustart testweise aktiviert. Startet die neue Version wiederholt nicht erfolgreich, schaltet ShopOS automatisch auf den vorherigen funktionierenden Bereich zurück.

Im Update Center können Administratoren System- und App-Updates suchen, installieren und den erforderlichen Neustart auslösen. Signatur, Dateigröße und SHA-256 werden vor einer Übernahme geprüft.

### Wichtiger Hinweis

Das Update Center ersetzt das erneute Flashen bei normalen Softwareänderungen. Ein physisch defektes Speichermedium oder ein vollständig zerstörtes Dateisystem kann trotzdem einen Austausch oder eine Neuinstallation erforderlich machen. Geschäftsdaten und Backups müssen zusätzlich extern gesichert werden.

### Enthaltene ShopOS-Funktionen

Dieses Image enthält unter anderem WooCommerce, das lokale ShopOS Control Center, Kunden- und Servicebereiche, den österreichischen Pilotbetrieb, ALSO-Katalog- und Inhaltsintegration, Office- und Fulfillment-Funktionen, DACH-Compliance-Prüfungen sowie das grafische Update Center für System und Apps.

Partnerprogramm-Aussagen, Logos, Zahlungsarten, Versand-, Steuer- und öffentliche Markteinstellungen bleiben kontrolliert deaktiviert, bis die jeweiligen Nachweise und realen Geschäftsdaten geprüft und freigegeben wurden.
EOF

sed \
    -e "s|@VERSION@|$version|g" \
    -e "s|@DESKTOP@|$desktop|g" \
    -e "s|@DESKTOP_SHA@|$desktop_sha|g" \
    -e "s|@LINUX@|$linux|g" \
    -e "s|@LINUX_SHA@|$linux_sha|g" \
    -e "s|@LAYOUT@|$layout|g" \
    -e "s|@VERSION_FILE@|$version_file|g" \
    -e "s|@EXTRACTED@|$extracted|g" \
    "$template"
