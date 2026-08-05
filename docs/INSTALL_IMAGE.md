# ShopOS-Image installieren

ShopOS wird einmalig auf eine SD-Karte oder vorzugsweise eine USB-SSD geschrieben. Normale spätere System- und App-Updates erfolgen anschließend im ShopOS Update Center.

## Download auswählen

| Betriebssystem | Empfohlene Datei | Verwendung |
|---|---|---|
| Windows 10/11 | `msfixit-shopos-rpi4-usb.img.zip` | ZIP vollständig entpacken und die enthaltene `.img` mit Raspberry Pi Imager schreiben |
| macOS | `msfixit-shopos-rpi4-usb.img.zip` | ZIP im Finder vollständig entpacken und die enthaltene `.img` mit Raspberry Pi Imager schreiben |
| Linux | `msfixit-shopos-rpi4-usb.img.xz` | Direkt mit Raspberry Pi Imager verwenden oder zuerst mit `xz` entpacken |

Das ZIP-Paket ist die grafische Desktop-Version für Windows und macOS. Das enthaltene Image wird vor dem Verpacken vollständig materialisiert und enthält nach dem Entpacken keine Sparse-Lücken. Dadurch soll Raspberry Pi Imager den Schreibfortschritt korrekt von 0 bis 100 Prozent anzeigen.

Ein separates DMG wird bewusst nicht angeboten: DMG ist ein macOS-Containerformat, während Raspberry Pi Imager für ShopOS das unveränderte Rohabbild im `.img`-Format benötigt. Ein DMG würde keinen technischen Vorteil bringen und nur ein weiteres großes, inhaltlich identisches Release-Asset erzeugen.

## Voraussetzungen

- Raspberry Pi 4 Model B
- mindestens 32 GB Zielmedium; eine USB-SSD mit 64 GB oder mehr wird empfohlen
- Raspberry Pi Imager 2.x
- stabile Stromversorgung
- vorherige Sicherung aller Daten auf dem Zielmedium

## Installation unter Windows

1. `msfixit-shopos-rpi4-usb.img.zip` und `msfixit-shopos-rpi4-usb.img.zip.sha256` herunterladen.
2. Das ZIP über **Alle extrahieren** vollständig entpacken.
3. Die `.img` nicht direkt aus 7-Zip, WinRAR oder dem ZIP-Ordner öffnen.
4. Raspberry Pi Imager starten und Raspberry Pi 4 als Modell auswählen.
5. **Eigenes Image verwenden** wählen und die entpackte `.img` auswählen.
6. Das richtige Zielmedium auswählen.
7. Schreiben starten und die anschließende Verifikation vollständig abwarten.

## Installation unter macOS

1. `msfixit-shopos-rpi4-usb.img.zip` und `msfixit-shopos-rpi4-usb.img.zip.sha256` herunterladen.
2. Das ZIP per Doppelklick im Finder vollständig entpacken.
3. Raspberry Pi Imager starten und Raspberry Pi 4 als Modell auswählen.
4. **Use custom** beziehungsweise **Eigenes Image verwenden** wählen.
5. Die entpackte `.img` und danach das richtige Zielmedium auswählen.
6. Das von macOS angeforderte Administratorkennwort bestätigen.
7. Schreiben und Verifikation vollständig abwarten.

Das Image wird nicht als macOS-Anwendung gestartet, sondern lediglich als Datenabbild im Raspberry Pi Imager ausgewählt. Dafür müssen Gatekeeper oder andere macOS-Sicherheitsfunktionen nicht deaktiviert werden.

## Installation unter Linux

Die XZ-Datei kann direkt in Raspberry Pi Imager ausgewählt werden. Alternativ kann sie vorher geprüft und entpackt werden:

```bash
sha256sum --check msfixit-shopos-rpi4-usb.img.xz.sha256
unxz msfixit-shopos-rpi4-usb.img.xz
```

Danach die `.img` mit Raspberry Pi Imager oder einem geeigneten Blockkopierwerkzeug schreiben.

## Prüfsumme kontrollieren

Jedes Downloadpaket besitzt eine eigene `.sha256`-Datei. Eine abweichende Prüfsumme bedeutet, dass die Datei beschädigt oder unvollständig ist. In diesem Fall nicht flashen, sondern erneut herunterladen.

## Nach dem Schreiben

1. Das Zielmedium erst nach erfolgreicher Verifikation auswerfen.
2. Medium in den Raspberry Pi einsetzen beziehungsweise anschließen.
3. Raspberry Pi starten und die Ersteinrichtung abschließen.
4. Danach im ShopOS Control Center das Update Center öffnen.
5. Künftige System- und App-Updates dort prüfen und installieren.

## Fortschrittsanzeige über 100 Prozent

Ältere XZ-Pakete konnten nach dem Entpacken Sparse-Lücken enthalten. Einige Kombinationen aus Desktop-Entpacker und Raspberry Pi Imager berechneten den Fortschritt dadurch anhand der physisch belegten statt der logischen Dateigröße und zeigten Werte über 100 Prozent. Das aktuelle ZIP-Paket für Windows und macOS wird deshalb ausdrücklich als vollständig belegtes Image erzeugt.

## Grenzen

Das Update Center verhindert bei normalen Softwareänderungen ein erneutes Flashen. Ein physisch defektes Speichermedium, ein vollständiger Datenträgerverlust oder eine beschädigte Boot-Partition kann weiterhin einen Austausch oder eine Neuinstallation erforderlich machen. Geschäftsdaten und Backups müssen zusätzlich extern gesichert werden.
