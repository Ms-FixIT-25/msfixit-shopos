# ShopOS Hardware Manager

## Ziel

Der ShopOS Hardware Manager überwacht Hardware und Betriebssystem lokal, erklärt Auffälligkeiten verständlich und trennt Beobachtung, Empfehlungen und reversible Optimierungen strikt voneinander. Standardmäßig werden keine Systemeinstellungen verändert und keine Hardwaredaten an externe Dienste übertragen.

## Architekturentscheidung

ShopOS ist heute überwiegend PHP/Bash mit systemd-Integration. Für einen dauerhaften, ressourcenschonenden Sensor- und Regelprozess wird ausschließlich die Python-Standardbibliothek ergänzt. Es wird kein Web-, ORM- oder Monitoring-Framework eingeführt.

Komponenten:

- `hardware_manager/platforms/`: Plattformadapter und stabile Hardware-Erkennung.
- `hardware_manager/sensors.py`: passive Messungen über Betriebssystem-Schnittstellen.
- `hardware_manager/thermal.py`: Zustandsautomat mit Hysterese, Mehrfachmessungen und Plausibilitätsprüfung.
- `hardware_manager/rules.py`: nachvollziehbare Optimierungsempfehlungen ohne automatische Änderung.
- `hardware_manager/api.py`: versionierte lokale JSON-API über Unix-Domain-Socket.
- `msfixit-hardware-manager`: langlebiger Daemon.
- `msfixit-hardware-action`: enger privilegierter Helper für vorab definierte reversible Aktionen.
- `/admin/hardware`: grafische ShopOS-Oberfläche für Status, Erklärungen, Empfehlungen und Diagnose.

Der Daemon und die GUI sind voneinander unabhängig. Ein GUI-Fehler darf Monitoring und thermische Zustandsbewertung nicht stoppen.

## Unterstützte Plattformen

### Linux

Unterstützt werden Raspberry Pi OS, Debian, Ubuntu und weitere Linux-Systeme mit `/proc` und `/sys`. Distribution und Version stammen aus `/etc/os-release`; CPU-, Speicher-, Netzwerk- und Datenträgerdaten werden über stabile Kernel-Schnittstellen gelesen.

### Raspberry Pi

Modell und Revision werden aus Device Tree und `/proc/cpuinfo` gelesen. Sofern `vcgencmd` verfügbar ist, wird `get_throttled` streng als Hex-Bitmaske ausgewertet. Undervoltage und Throttling werden sowohl als aktueller als auch als historischer Zustand erfasst.

### macOS

Der Adapter unterscheidet Intel und Apple Silicon über `uname`/`platform.machine()` und feste `sysctl`-Abfragen. Nicht öffentlich stabil verfügbare Sensorwerte, insbesondere Apple-Silicon-Temperaturen, werden ausdrücklich als `unavailable` gemeldet und nicht erfunden. Die Debian-ShopOS-Distribution installiert aktuell keinen macOS LaunchDaemon; eine Apple-konforme Paketierung bleibt ein separater Ausbauschritt.

## Messstrategie und Ressourcenbudget

- Standardintervall: 30 Sekunden.
- Keine aktiven Internet-Speedtests ohne ausdrückliche Zustimmung.
- Netzwerkstatus ist standardmäßig passiv; Paket- und Bytezähler kommen aus Kernel-Schnittstellen.
- Historische Rohwerte bleiben als begrenzter In-Memory-Ring erhalten.
- Persistente Snapshots werden höchstens alle fünf Minuten atomar geschrieben, um SD-/SSD-Schreiblast zu reduzieren.
- Ereignisse gehen zusätzlich ins systemd-Journal.
- Der systemd-Dienst erhält niedrige CPU-/I/O-Priorität und ein eigenes Speicherlimit.

## Temperaturmodell

Zustände:

1. `normal`
2. `elevated`
3. `warning`
4. `critical`
5. `emergency`

Für Raspberry Pi 4 gilt als Hardwareobergrenze die offizielle 85-°C-Drosselgrenze. ShopOS warnt deutlich vorher. Zustandswechsel nach oben verlangen mehrere plausible Messungen; Wechsel nach unten verwenden Hysterese. Eine kontrollierte Abschaltung ist standardmäßig deaktiviert und kann nur in `automatic` zusammen mit einer gesonderten Einstellung aktiviert werden. Ein einzelner Messwert darf niemals eine Abschaltung auslösen.

## Betriebsarten

- `observe`: nur messen und erklären.
- `recommend`: Änderungen vorschlagen; Ausführung verlangt ausdrückliche Bestätigung.
- `automatic`: nur als `automatable` markierte, getestete und reversible Regeln dürfen automatisch angewandt werden. Kritische Aktionen bleiben bestätigungspflichtig.

Standard ist `observe`.

## Sicherheitsmodell

### Daemon

Der Daemon läuft unter einem eigenen Systemkonto ohne Login-Shell. Er benötigt für normale Messungen keine Root-Rechte. systemd schützt Dateisystem, Home-Verzeichnisse, Kernel-Tunables und Control Groups vor Schreibzugriffen.

### API

Die lokale API verwendet einen Unix-Domain-Socket unter `/run/msfixit-shopos/hardware-manager.sock`; es wird kein TCP-Port geöffnet. Anfragen enthalten eine feste API-Version. Schreibaktionen sind in der API nur als definierte Aktions-IDs zulässig. Freie Shell-Befehle, Pfade oder beliebige systemd-Units sind nicht Teil des Protokolls.

### Privilegierte Änderungen

Privilegierte Änderungen erfolgen ausschließlich über `msfixit-hardware-action`. Der Helper akzeptiert nur feste Aktionen und streng validierte Parameter, legt vor Änderungen eine Transaktion an und kann diese über ihre zufällige Transaktions-ID zurückrollen. Die GUI darf keine Shell-Befehle zusammensetzen.

## Erste sichere Optimierungen

Der erste Implementierungsstand analysiert insbesondere:

- aktuelle CPU-Governor-Einstellung und verfügbare Governor;
- Speicherdruck und Swap-Nutzung, ohne Swap pauschal als Fehler zu werten;
- freien Datenträgerplatz;
- Temperatur und Drosselung;
- Raspberry-Pi-Undervoltage;
- USB-3-Geräte, die nur mit High-Speed/USB-2 laufen;
- passive Netzwerkfehler, WLAN-Signal und Link-Geschwindigkeit;
- auffällige ShopOS-Dienste;
- TRIM-Fähigkeit des Bootmediums.

Automatisch änderbar werden zunächst nur klar reversible Einstellungen zugelassen. Overclocking, Spannungsanhebung und Firmware-Manipulation sind ausdrücklich ausgeschlossen.

## Datenschutz

Telemetrie und externe Übertragung sind standardmäßig deaktiviert. Diagnoseexporte enthalten eine Vorschau und entfernen Secrets, Tokens, Passwörter, MAC-Adressen und öffentliche IP-Adressen, soweit sie in den exportierten Daten vorkommen.

## Primärquellen und technische Entscheidungen

- Linux Kernel hwmon: https://docs.kernel.org/hwmon/
- Linux hwmon sysfs ABI: https://docs.kernel.org/hwmon/sysfs-interface.html
- Linux CPUFreq: https://docs.kernel.org/admin-guide/pm/cpufreq.html
- Linux Thermal sysfs: https://docs.kernel.org/driver-api/thermal/sysfs-api.html
- Raspberry Pi Hardware/Temperatur: https://www.raspberrypi.com/documentation/computers/raspberry-pi.html
- Raspberry Pi OS `vcgencmd get_throttled`: https://www.raspberrypi.com/documentation/computers/os.html
- systemd.exec Hardening: https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html

Direkte `/sys/class/hwmon`-Werte werden nur nach Einheiten- und Plausibilitätsprüfung verwendet. Die Kernel-Dokumentation weist darauf hin, dass Sensorlabels und Board-Verschaltung hardwareabhängig sind; deshalb darf der Manager unklare Sensoren nicht automatisch als CPU-Sensor deklarieren.

## Noch nicht als echte Hardware validiert

- macOS Intel und Apple Silicon: Adaptertests laufen nur mit Fixtures/Mocks, solange keine passende Hardware im CI verfügbar ist.
- Lüfterregelung: wird zunächst nur erkannt, nicht automatisch verändert.
- SMART/NVMe: die Architektur sieht Adapter vor; die Basispaketierung führt noch keine zusätzliche SMART-Abhängigkeit ein.
- aktive Internetgeschwindigkeitstests: nicht Bestandteil des Standardmonitorings.
