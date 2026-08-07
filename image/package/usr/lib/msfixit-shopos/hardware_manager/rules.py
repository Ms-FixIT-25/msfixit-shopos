from __future__ import annotations

from hardware_manager.models import CpuSnapshot, MemorySnapshot, NetworkInterface, Recommendation, ServiceSnapshot, StorageSnapshot, ThermalSnapshot, UsbDevice


def _pct(part: int | None, total: int | None) -> float | None:
    if part is None or total is None or total <= 0:
        return None
    return part * 100.0 / total


class RuleEngine:
    def evaluate(self, *, platform_family: str, cpu: CpuSnapshot, memory: MemorySnapshot, thermal: ThermalSnapshot, storage: StorageSnapshot, network: list[NetworkInterface], usb: list[UsbDevice], services: list[ServiceSnapshot]) -> list[Recommendation]:
        recommendations: list[Recommendation] = []
        if thermal.level in {"warning", "critical", "emergency"}:
            recommendations.append(Recommendation("thermal-pressure", "critical" if thermal.level in {"critical", "emergency"} else "warning", "Temperatur braucht Aufmerksamkeit", f"Das System befindet sich in der Temperaturstufe {thermal.level}.", "Anhaltende Last, eingeschränkte Luftzufuhr oder unzureichende Kühlung sind typische Ursachen.", "Hohe Temperaturen können Taktreduzierung, langsamere Antworten und im Extremfall Schutzabschaltungen verursachen.", "Kühlung und Luftweg prüfen; besonders belastende Prozesse und Dienste kontrollieren.", "Mehr Leistungsreserve und weniger thermische Drosselung.", "Keine Änderung wird automatisch erzwungen. Aggressives Overclocking ist ausgeschlossen.", "Keine Berechtigung für die Analyse; Dienständerungen benötigen Bestätigung.", True, False))
        if thermal.current_undervoltage or thermal.undervoltage_occurred:
            current = bool(thermal.current_undervoltage)
            recommendations.append(Recommendation("pi-undervoltage", "critical" if current else "warning", "Raspberry-Pi-Stromversorgung prüfen", "Aktuelle Unterspannung erkannt." if current else "Seit dem Start wurde mindestens einmal Unterspannung erkannt.", "Netzteil, Kabel, Steckverbindung oder hohe USB-Last können die Versorgungsspannung absenken.", "Unterspannung kann CPU-Takt begrenzen, USB-/Datenträgerfehler begünstigen und Instabilität verursachen.", "Geeignetes Netzteil, kurzes hochwertiges Kabel und die Stromaufnahme angeschlossener USB-Geräte prüfen.", "Stabilere Leistung und weniger vermeidbare Drosselung oder I/O-Fehler.", "Keine Softwareänderung erforderlich.", "Keine.", True, False))
        available_pct = _pct(memory.available_bytes, memory.total_bytes)
        swap_used = None
        if memory.swap_total_bytes is not None and memory.swap_free_bytes is not None:
            swap_used = max(0, memory.swap_total_bytes - memory.swap_free_bytes)
        swap_pct = _pct(swap_used, memory.swap_total_bytes)
        if available_pct is not None and available_pct < 15.0:
            recommendations.append(Recommendation("memory-pressure", "warning" if available_pct >= 8.0 else "critical", "Arbeitsspeicher wird knapp", f"Nur noch rund {available_pct:.0f} % des RAM sind als verfügbar gemeldet.", "Viele gleichzeitige PHP-/Datenbankprozesse, große Caches oder einzelne speicherintensive Dienste können Druck erzeugen.", "Das System kann stärker auslagern und dadurch deutlich langsamer reagieren.", "Zuerst die größten Dienste prüfen; erst danach Cache- oder Workergrenzen anpassen.", "Weniger Swap-I/O und gleichmäßigere Antwortzeiten.", "Zu kleine Limits können legitime Lastspitzen ausbremsen; deshalb keine blinde automatische Kürzung.", "Analyse ohne Administratorrechte; Konfigurationsänderungen nur bestätigt.", True, False))
        elif swap_pct is not None and swap_pct > 25.0:
            recommendations.append(Recommendation("swap-active", "notice", "Swap wird genutzt – noch kein Fehler", f"Etwa {swap_pct:.0f} % des konfigurierten Swap sind belegt.", "Linux kann selten benötigte Seiten auslagern, selbst wenn noch RAM verfügbar ist.", "Allein die Swap-Nutzung beweist keinen Engpass; problematisch wird sie zusammen mit wenig verfügbarem RAM und hoher I/O-Wartezeit.", "Verlauf von RAM, I/O-Wartezeit und Swap gemeinsam beobachten.", "Vermeidet unnötiges Tuning aufgrund eines einzelnen Werts.", "Keine Änderung.", "Keine.", True, False))
        free_pct = _pct(storage.free_bytes, storage.total_bytes)
        if free_pct is not None and free_pct < 15.0:
            recommendations.append(Recommendation("storage-low", "critical" if free_pct < 7.0 else "warning", "Freier Speicher wird knapp", f"Auf {storage.mountpoint} sind nur noch rund {free_pct:.0f} % frei.", "Shopdaten, Backups, Logs oder Importdaten wachsen auf dem persistenten Datenträger.", "Datenbank, Updates und Backups können bei sehr wenig freiem Speicher fehlschlagen.", "Große Datenbereiche prüfen und alte, entbehrliche Daten kontrolliert archivieren oder auslagern.", "Mehr Reserve für Datenbank, Updates und temporäre Dateien.", "Automatisches Löschen ist ausdrücklich nicht erlaubt.", "Löschen oder Verschieben nur nach ausdrücklicher Bestätigung.", False, False))
        if cpu.iowait_percent is not None and cpu.iowait_percent >= 10.0:
            recommendations.append(Recommendation("io-wait-high", "warning", "Datenträger bremst die CPU aus", f"Die CPU wartet aktuell zu {cpu.iowait_percent:.1f} % auf I/O.", "Langsames Medium, starke Datenbank-/Log-Schreiblast oder ein USB-Gerät am ungeeigneten Anschluss sind mögliche Ursachen.", "Bestellungen und Admin-Seiten können trotz niedriger CPU-Auslastung träge wirken.", "Datenträgeraktivität und USB-Link prüfen; bei SD-Karten unnötige Schreiblast reduzieren.", "Kürzere Wartezeiten und weniger Dauerlast.", "Keine automatische Änderung anhand einer einzelnen Messung.", "Keine für die Diagnose.", True, False))
        if platform_family == "raspberry-pi" and cpu.governor == "performance" and "schedutil" in cpu.available_governors and cpu.utilization_percent is not None and cpu.utilization_percent < 25.0:
            recommendations.append(Recommendation("governor-schedutil", "notice", "CPU kann im Leerlauf sparsamer arbeiten", "Der Governor steht dauerhaft auf performance, obwohl die aktuelle Last niedrig ist.", "Der Performance-Governor hält höhere Frequenzen aggressiver bereit.", "Im Dauerbetrieb kann das unnötig Energie und thermische Reserve kosten.", "Auf schedutil wechseln; dieser Governor passt den Takt dynamisch an die angeforderte CPU-Kapazität an.", "Niedrigere Leerlaufleistung bei weiterhin schneller Lastreaktion.", "Bei Spezial-Workloads kann die Latenz minimal anders ausfallen; Änderung ist vollständig rückrollbar.", "Administratorrechte erforderlich.", True, True, "set-governor", "schedutil"))
        for device in usb:
            spec = device.usb_spec or ""
            if spec.startswith("3") and device.negotiated_mbps is not None and device.negotiated_mbps <= 480.0:
                name = device.product or f"USB {device.vendor_id}:{device.product_id}"
                recommendations.append(Recommendation(f"usb-speed-{device.sysfs_name}", "warning", "USB-3-Gerät läuft nur mit USB-2-Geschwindigkeit", f"{name} meldet USB {spec}, handelt aber nur {device.negotiated_mbps:.0f} Mbit/s aus.", "USB-2-Port, ungeeignetes Kabel, Hub oder Signalproblem sind typische Ursachen.", "Datenträger und Adapter können deutlich unter ihrer möglichen Leistung bleiben.", "Gerät an einen USB-3-Port anschließen und Kabel/Hub prüfen.", "Höherer Datendurchsatz und weniger I/O-Wartezeit.", "Keine Softwareänderung.", "Keine.", True, False))
        for interface in network:
            if interface.state != "up":
                continue
            if interface.duplex == "half" and interface.speed_mbps:
                recommendations.append(Recommendation(f"network-duplex-{interface.name}", "warning", "Netzwerk läuft nur im Half-Duplex-Modus", f"{interface.name} meldet {interface.speed_mbps} Mbit/s Half Duplex.", "Kabel, Switch-Port oder Aushandlung können die Verbindung begrenzen.", "Kollisionen und verringerter Durchsatz sind möglich.", "Kabel und Switch-Port prüfen; keine MTU-/Treiberwerte auf Verdacht verändern.", "Stabilere Vollduplex-Verbindung.", "Keine automatische Netzwerkkonfigurationsänderung.", "Keine.", True, False))
            if (interface.rx_errors or 0) + (interface.tx_errors or 0) > 0:
                recommendations.append(Recommendation(f"network-errors-{interface.name}", "notice", f"Netzwerkfehler auf {interface.name} protokolliert", "Der Kernel zählt fehlerhafte empfangene oder gesendete Pakete.", "Kabel, Stecker, Funkqualität oder Treiber können beteiligt sein.", "Bei fortlaufendem Anstieg können Übertragungen wiederholt werden und langsamer wirken.", "Beobachten, ob die Fehlerzähler zwischen Messungen weiter steigen; erst dann gezielt Verbindung prüfen.", "Verhindert vorschnelle Diagnose anhand alter Zählerstände.", "Keine Änderung.", "Keine.", True, False))
            if interface.wireless_signal_dbm is not None and interface.wireless_signal_dbm < -75.0:
                recommendations.append(Recommendation(f"wifi-signal-{interface.name}", "warning", "WLAN-Signal ist schwach", f"{interface.name} meldet ungefähr {interface.wireless_signal_dbm:.0f} dBm.", "Entfernung, Wände, ungünstige Antennenposition oder Funkstörungen können die Verbindung schwächen.", "Höhere Latenz, geringerer Durchsatz und Paketwiederholungen sind wahrscheinlicher.", "Pi/Access Point günstiger positionieren oder für den Shopbetrieb Ethernet bevorzugen.", "Stabilere Netzwerkreaktion ohne zusätzliche CPU-Last.", "Keine Softwareänderung.", "Keine.", True, False))
        total_ram = memory.total_bytes or 0
        for service in services:
            if service.active_state == "failed":
                recommendations.append(Recommendation(f"service-failed-{service.unit}", "critical", f"Dienstfehler: {service.unit}", "systemd meldet den Dienst als fehlgeschlagen.", "Die konkrete Ursache steht im Dienstprotokoll und darf nicht geraten werden.", "Je nach Dienst können Shop, Datenbank, Cache oder Hintergrundfunktionen betroffen sein.", "Protokoll und Abhängigkeiten prüfen; erst danach einen kontrollierten Neustart erwägen.", "Ursachenbasierte Fehlerbehebung statt Neustart auf Verdacht.", "Ein Neustart kann laufende Arbeit unterbrechen.", "Administratorrechte für Dienständerungen.", True, False))
            if total_ram > 0 and service.memory_bytes is not None and service.memory_bytes > total_ram * 0.35:
                recommendations.append(Recommendation(f"service-memory-{service.unit}", "warning", f"Hoher Speicheranteil: {service.unit}", "Ein einzelner ShopOS-Dienst belegt mehr als 35 % des gesamten RAM.", "Lastspitze, Cachewachstum oder ungeeignete Workergrenzen sind mögliche Ursachen.", "Andere Dienste geraten schneller unter Speicherdruck.", "Verlauf und konkrete Dienstmetriken prüfen, bevor Limits verändert werden.", "Gezieltes statt pauschales Ressourcen-Tuning.", "Zu harte Limits können legitime Bestellspitzen ausbremsen.", "Keine für Diagnose; Änderungen bestätigt.", True, False))
        return recommendations
