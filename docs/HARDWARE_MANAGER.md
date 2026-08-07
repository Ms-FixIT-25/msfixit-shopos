# ShopOS Hardware Manager

## Status

Der Hardware Manager ist der zentrale, leichtgewichtige Hardware-/Ressourcenbaustein von ShopOS. Er läuft als unprivilegierter Hintergrunddienst und stellt seine Daten über eine lokale Unix-Socket-API für das ShopOS Control Center bereit.

Aktuell implementiert und statisch/unit-testbar:

- Raspberry-Pi-, allgemeine Linux- und konservative macOS-Plattformerkennung
- CPU, Architektur, Kernel, Distribution/OS, RAM und physische/logische Kerne
- Erkennung einfacher Virtualisierungsmarker unter Linux
- CPU-Auslastung, I/O-Wait, Load, Frequenz und Governor
- RAM und Swap
- Thermal-/hwmon-Sensoren
- Raspberry-Pi-`get_throttled` für aktuelle/historische Unterspannung und Throttling, sofern `vcgencmd` verfügbar ist
- persistenter Datenträger, Dateisystem, freier Speicher, Boot-Medium und TRIM-Hinweis
- Netzwerkinterface, Link-Speed, Duplex, MTU, WLAN-Signal und Kernel-Fehlerzähler
- USB-Geräte und ausgehandelte USB-Geschwindigkeit
- lokale CUPS-Drucker, soweit `lpstat` verfügbar ist
- ShopOS-/Webstack-systemd-Dienste und deren Speicherverbrauch
- erklärbare Empfehlungen mit Nutzen, Risiko, Berechtigung und Reversibilität
- Betriebsarten `observe`, `recommend`, `automatic`
- ausschließlich eng freigegebene reversible automatische Aktion: CPU-Governor `performance` → `schedutil` auf Raspberry Pi unter niedriger Last
- transaktionaler Rollback für Governor-Änderungen
- Control-Center-GUI unter `/admin/hardware`

## Sicherheitsmodell

Der Messdienst läuft als `shopos-hwmon`, nicht als root. PHP/Nginx besitzen **keinen** direkten sudo-Zugriff auf den Root-Helper.

Kommunikationsweg:

`Browser → authentifizierte Admin-PHP-Seite → Unix-Socket → shopos-hwmon → enger sudo-Helper → erlaubte sysfs-Änderung`

Der Unix-Socket ist über die eigene Gruppe `shopos-hwapi` zwischen `www-data` und `shopos-hwmon` geteilt. Dadurch muss der Hardware-Dienst nicht Mitglied der allgemeinen `www-data`-Gruppe sein und kann insbesondere keine gruppenlesbaren ShopOS-Secrets erben.

Der Root-Helper akzeptiert nur:

- `apply set-governor schedutil`
- `apply set-governor powersave`
- `rollback <24-stellige Transaktions-ID>`

Er validiert ausschließlich feste `/sys/devices/system/cpu/cpufreq/policyN/scaling_governor`-Pfade, legt vor Änderungen einen root-only Transaktionsdatensatz an und verifiziert den geschriebenen Wert.

Nicht implementiert:

- freie Shell-Befehle
- freie sysfs-Pfade
- Overclocking
- Spannungsanhebung
- `force_turbo`
- automatisches Löschen von Daten
- automatische MTU-/Treiber-/Netzwerkänderungen

## Temperaturmodell

Die Raspberry-Pi-Standardpolitik verwendet:

| Stufe | Schwelle |
|---|---:|
| elevated | 60 °C |
| warning | 70 °C |
| critical | 78 °C |
| emergency | 83 °C |

Ein Zustandswechsel nach oben benötigt mehrere bestätigte Messungen. Das Absenken verwendet zusätzliche Hysterese und mehrere kühlere Messungen. Ein einzelner Sensorwert darf damit keine Notfallaktion auslösen.

Der Code kann eine über mindestens 120 Sekunden bestätigte Emergency-Situation als `shutdown_eligible` markieren. **Eine automatische Abschaltung wird im aktuellen Produktstand absichtlich nicht ausgeführt.** Die Ausführung bleibt blockiert, bis Issue #45 eine reale Raspberry-Pi-Hardwarevalidierung mit thermischen Tests und kontrollierter Notfallmatrix liefert.

## Ressourcenprofil

Der Dienst ist bewusst klein gehalten:

- Standard-Sampling: 30 s
- persistenter Snapshot: höchstens alle 5 min
- bounded In-Memory-Historie
- `CPUQuota=20%`
- `CPUWeight=5`
- `MemoryHigh=64M`
- `MemoryMax=96M`
- `TasksMax=48`
- `Nice=10`
- `IOSchedulingClass=idle`

Die meisten Messungen lesen vorhandene Kernelzähler in `/proc` und `/sys`; es wird kein Benchmark-Dauerfeuer erzeugt.

## Plattformgrenzen

### Raspberry Pi

Referenzplattform. Pi-spezifische Undervoltage-/Throttling-Daten werden nur dort interpretiert. Governor-Automatik ist ebenfalls auf Raspberry Pi beschränkt.

### Allgemeines Linux / VM

Linux-Kernelmetriken werden verwendet, soweit vorhanden. Raspberry-Pi-spezifische Optimierungen werden nicht angewandt. Virtualisierung wird, soweit möglich, als Capability-/Plattformhinweis erfasst.

### macOS

Der Adapter kann Architektur, CPU/Modell und Kernanzahl aus stabilen Systeminformationen ableiten. Es wird **keine Temperatur erfunden**, wenn keine stabile öffentliche Basisschnittstelle verfügbar ist. Linux-/sysfs-Tuning wird niemals auf macOS angewandt.

## Datenschutz

Der Hardware Manager erfasst bewusst keine:

- Passwörter
- Tokens
- IP-Adressen
- MAC-Adressen
- Dateiinhalte von Kundendaten

Diagnoseexporte bestehen aus Hardware-/Kernelzuständen, Empfehlungen und eigenen Events.

## Teststatus

Automatisierbar und vorgesehen:

- Python-Kompilierung
- Plattform-/Capability-Verträge
- Thermal-Hysterese und Mehrfachmessungen
- Emergency-Eligibility ohne reale Abschaltung
- Raspberry-Pi-only Governorregel
- systemd-Ressourcenlimits
- sudoers-Grenzen
- Nginx-/PHP-/CSRF-/Socket-Verträge
- Netzwerk-/USB-/Druckersensor-Verträge
- Packaging
- Image Build
- ARM64-QEMU-Boot

Nicht durch QEMU beweisbar und separat als reale Hardwaretests zu dokumentieren:

- echte SoC-Temperaturentwicklung
- reales `get_throttled`/Unterspannungsverhalten unter Last
- reale HDMI-/Kiosk-Wechselwirkung
- USB-/NVMe-/SSD-Leistung verschiedener Controller
- echte WLAN-/Ethernet-Linkqualität
- thermische Schutzmaßnahmen und kontrollierte Notabschaltung

Diese Punkte bleiben Teil des Production-Gates #45.
