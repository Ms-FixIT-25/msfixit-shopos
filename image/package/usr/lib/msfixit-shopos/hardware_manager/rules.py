from __future__ import annotations

from hardware_manager.models import (
    CpuSnapshot,
    MemorySnapshot,
    NetworkInterface,
    Recommendation,
    ServiceSnapshot,
    StorageSnapshot,
    ThermalSnapshot,
    UsbDevice,
)


def _pct(part: int | None, total: int | None) -> float | None:
    if part is None or total is None or total <= 0:
        return None
    return part * 100.0 / total


class RuleEngine:
    def evaluate(
        self,
        *,
        platform_family: str,
        cpu: CpuSnapshot,
        memory: MemorySnapshot,
        thermal: ThermalSnapshot,
        storage: StorageSnapshot,
        network: list[NetworkInterface],
        usb: list[UsbDevice],
        services: list[ServiceSnapshot],
    ) -> list[Recommendation]:
        recommendations: list[Recommendation] = []

        if thermal.level in {"warning", "critical", "emergency"}:
            severity = "critical" if thermal.level in {"critical", "emergency"} else "warning"
            recommendations.append(
                Recommendation(
                    id="thermal-pressure",
                    severity=severity,
                    title="Temperatur braucht Aufmerksamkeit",
                    problem=f"Das System befindet sich in der Temperaturstufe {thermal.level}.",
                    cause="Anhaltende Last, eingeschränkte Luftzufuhr oder unzureichende Kühlung sind typische Ursachen.",
                    impact="Hohe Temperaturen können Taktreduzierung, langsamere Antworten und im Extremfall Schutzabschaltungen verursachen.",
                    action="Kühlung und Luftweg prüfen; besonders belastende Prozesse und Dienste kontrollieren.",
                    expected_benefit="Mehr Leistungsreserve und weniger thermische Drosselung.",
                    risk="Keine Änderung wird automatisch erzwungen. Aggressives Overclocking ist ausgeschlossen.",
                    permission="Keine Berechtigung für die Analyse; Dienständerungen benötigen Bestätigung.",
                    reversible=True,
                    automatable=False,
                )
            )

        if thermal.current_undervoltage or thermal.undervoltage_occurred:
            current = bool(thermal.current_undervoltage)
            recommendations.append(
                Recommendation(
                    id="pi-undervoltage",
                    severity="critical" if current else "warning",
                    title="Raspberry-Pi-Stromversorgung prüfen",
                    problem="Aktuelle Unterspannung erkannt." if current else "Seit dem Start wurde mindestens einmal Unterspannung erkannt.",
                    cause="Netzteil, Kabel, Steckverbindung oder hohe USB-Last können die Versorgungsspannung absenken.",
                    impact="Unterspannung kann CPU-Takt begrenzen, USB-/Datenträgerfehler begünstigen und Instabilität verursachen.",
                    action="Geeignetes Netzteil, kurzes hochwertiges Kabel und die Stromaufnahme angeschlossener USB-Geräte prüfen.",
                    expected_benefit="Stabilere Leistung und weniger vermeidbare Drosselung oder I/O-Fehler.",
                    risk="Keine Softwareänderung erforderlich.",
                    permission="Keine.",
                    reversible=True,
                    automatable=False,
                )
            )

        available_pct = _pct(memory.available_bytes, memory.total_bytes)
        swap_used = None
        if memory.swap_total_bytes is not None and memory.swap_free_bytes is not None:
            swap_used = max(0, memory.swap_total_bytes - memory.swap_free_bytes)
        swap_pct = _pct(swap_used, memory.swap_total_bytes)
        if available_pct is not None and available_pct < 15.0:
            recommendations.append(
                Recommendation(
                    id="memory-pressure",
                    severity="warning" if available_pct >= 8.0 else "critical",
                    title="Arbeitsspeicher wird knapp",
                    problem=f"Nur noch rund {available_pct:.0f} % des RAM sind als verfügbar gemeldet.",
                    cause="Viele gleichzeitige PHP-/Datenbankprozesse, große Caches oder einzelne speicherintensive Dienste können Druck erzeugen.",
                    impact="Das System kann stärker auslagern und dadurch deutlich langsamer reagieren.",
                    action="Zuerst die größten Dienste prüfen; erst danach Cache- oder Workergrenzen anpassen.",
                    expected_benefit="Weniger Swap-I/O und gleichmäßigere Antwortzeiten.",
                    risk="Zu kleine Limits können legitime Lastspitzen ausbremsen; deshalb keine blinde automatische Kürzung.",
                    permission="Analyse ohne Administratorrechte; Konfigurationsänderungen nur bestätigt.",
                    reversible=True,
                    automatable=False,
                )
            )
        elif swap_pct is not None and swap_pct > 25.0:
            recommendations.append(
                Recommendation(
                    id="swap-active",
                    severity="notice",
                    title="Swap wird genutzt – noch kein Fehler",
                    problem=f"Etwa {swap_pct:.0f} % des konfigurierten Swap sind belegt.",
                    cause="Linux kann selten benötigte Seiten auslagern, selbst wenn noch RAM verfügbar ist.",
                    impact="Allein die Swap-Nutzung beweist keinen Engpass; problematisch wird sie zusammen mit wenig verfügbarem RAM und hoher I/O-Wartezeit.",
                    action="Verlauf von RAM, I/O-Wartezeit und Swap gemeinsam beobachten.",
                    expected_benefit="Vermeidet unnötiges Tuning aufgrund eines einzelnen Werts.",
                    risk="Keine Änderung.",
                    permission="Keine.",
                    reversible=True,
                    automatable=False,
                )
            )

        free_pct = _pct(storage.free_bytes, storage.total_bytes)
        if free_pct is not None and free_pct < 15.0:
            recommendations.append(
                Recommendation(
                    id="storage-low",
                    severity="critical" if free_pct < 7.0 else "warning",
                    title="Freier Speicher wird knapp",
                    problem=f"Auf {storage.mountpoint} sind nur noch rund {free_pct:.0f} % frei.",
                    cause="Shopdaten, Backups, Logs oder Importdaten wachsen auf dem persistenten Datenträger.",
                    impact="Datenbank, Updates und Backups können bei sehr wenig freiem Speicher fehlschlagen.",
                    action="Große Datenbereiche prüfen und alte, entbehrliche Daten kontrolliert archivieren oder auslagern.",
                    expected_benefit="Mehr Reserve für Datenbank, Updates und temporäre Dateien.",
                    risk="Automatisches Löschen ist ausdrücklich nicht erlaubt.",
                    permission="Löschen oder Verschieben nur nach ausdrücklicher Bestätigung.",
                    reversible=False,
                    automatable=False,
                )
            )

        if cpu.iowait_percent is not None and cpu.iowait_percent >= 10.0:
            recommendations.append(
                Recommendation(
                    id="io-wait-high",
                    severity="warning",
                    title="Datenträger bremst die CPU aus",
                    problem=f"Die CPU wartet aktuell zu {cpu.iowait_percent:.1f} % auf I/O.",
                    cause="Langsames Medium, starke Datenbank-/Log-Schreiblast oder ein USB-Gerät am ungeeigneten Anschluss sind mögliche Ursachen.",
                    impact="Bestellungen und Admin-Seiten können trotz niedriger CPU-Auslastung träge wirken.",
                    action="Datenträgeraktivität und USB-Link prüfen; bei SD-Karten unnötige Schreiblast reduzieren.",
                    expected_benefit="Kürzere Wartezeiten und weniger Dauerlast.",
                    risk="Keine automatische Änderung anhand einer einzelnen Messung.",
                    permission="Keine für die Diagnose.",
                    reversible=True,
                    automatable=False,
                )
            )

        if (
            platform_family == "raspberry-pi"
            and cpu.governor == "performance"
            and "schedutil" in cpu.available_governors
            and cpu.utilization_percent is not None
            and cpu.utilization_percent < 25.0
        ):
            recommendations.append(
                Recommendation(
                    id="governor-schedutil",
                    severity="notice",
                    title="CPU kann im Leerlauf sparsamer arbeiten",
                    problem="Der Governor steht dauerhaft auf performance, obwohl die aktuelle Last niedrig ist.",
                    cause="Der Performance-Governor hält höhere Frequenzen aggressiver bereit.",
                    impact="Im Dauerbetrieb kann das unnötig Energie und thermische Reserve kosten.",
                    action="Auf schedutil wechseln; dieser Governor passt den Takt dynamisch an die angeforderte CPU-Kapazität an.",
                    expected_benefit="Niedrigere Leerlaufleistung bei weiterhin schneller Lastreaktion.",
                    risk="Bei Spezial-Workloads kann die Latenz minimal anders ausfallen; Änderung ist vollständig rückrollbar.",
                    permission="Administratorrechte erforderlich.",
                    reversible=True,
                    automatable=True,
                    action_id="set-governor",
                    action_value="schedutil",
                )
            )

        for device in usb:
            spec = device.usb_spec or ""
            if spec.startswith("3") and device.negotiated_mbps is not None and device.negotiated_mbps <= 480.0:
                name = device.product or f"USB {device.vendor_id}:{device.product_id}"
                recommendations.append(
                    Recommendation(
                        id=f"usb-speed-{device.sysfs_name}",
                        severity="warning",
                        title="USB-3-Gerät läuft nur mit USB-2-Geschwindigkeit",
                        problem=f"{name} meldet USB {spec}, handelt aber nur {device.negotiated_mbps:.0f} Mbit/s aus.",
                        cause="USB-2-Port, ungeeignetes Kabel, Hub oder Signalproblem sind typische Ursachen.",
                        impact="Datenträger und Adapter können deutlich unter ihrer möglichen Leistung bleiben.",
                        action="Gerät an einen USB-3-Port anschließen und Kabel/Hub prüfen.",
                        expected_benefit="Höherer Datendurchsatz und weniger I/O-Wartezeit.",
                        risk="Keine Softwareänderung.",
                        permission="Keine.",
                        reversible=True,
                        automatable=False,
                    )
                )

        for interface in network:
            if interface.state != "up":
                continue
            if (interface.rx_errors or 0) + (interface.tx_errors or 0) > 0:
                recommendations.append(
                    Recommendation(
                        id=f"network-errors-{interface.name}",
                        severity="notice",
                        title=f"Netzwerkfehler auf {interface.name} protokolliert",
                        problem="Der Kernel zählt fehlerhafte empfangene oder gesendete Pakete.",
                        cause="Kabel, Stecker, Funkqualität oder Treiber können beteiligt sein.",
                        impact="Bei fortlaufendem Anstieg können Übertragungen wiederholt werden und langsamer wirken.",
                        action="Beobachten, ob die Fehlerzähler zwischen Messungen weiter steigen; erst dann gezielt Verbindung prüfen.",
                        expected_benefit="Verhindert vorschnelle Diagnose anhand alter Zählerstände.",
                        risk="Keine Änderung.",
                        permission="Keine.",
                        reversible=True,
                        automatable=False,
                    )
                )
            if interface.wireless_signal_dbm is not None and interface.wireless_signal_dbm < -75.0:
                recommendations.append(
                    Recommendation(
                        id=f"wifi-signal-{interface.name}",
                        severity="warning",
                        title="WLAN-Signal ist schwach",
                        problem=f"{interface.name} meldet ungefähr {interface.wireless_signal_dbm:.0f} dBm.",
                        cause="Entfernung, Wände, ungünstige Antennenposition oder Funkstörungen können die Verbindung schwächen.",
                        impact="Höhere Latenz, geringerer Durchsatz und Paketwiederholungen sind wahrscheinlicher.",
                        action="Pi/Access Point günstiger positionieren oder für den Shopbetrieb Ethernet bevorzugen.",
                        expected_benefit="Stabilere Netzwerkreaktion ohne zusätzliche CPU-Last.",
                        risk="Keine Softwareänderung.",
                        permission="Keine.",
                        reversible=True,
                        automatable=False,
                    )
                )

        total_ram = memory.total_bytes or 0
        for service in services:
            if service.active_state == "failed":
                recommendations.append(
                    Recommendation(
                        id=f"service-failed-{service.unit}",
                        severity="critical",
                        title=f"Dienstfehler: {service.unit}",
                        problem="systemd meldet den Dienst als fehlgeschlagen.",
                        cause="Die konkrete Ursache steht im Dienstprotokoll und darf nicht geraten werden.",
                        impact="Je nach Dienst können Shop, Datenbank, Cache oder Hintergrundfunktionen betroffen sein.",
                        action="Protokoll und Abhängigkeiten prüfen; erst danach einen kontrollierten Neustart erwägen.",
                        expected_benefit="Ursachenbasierte Fehlerbehebung statt Neustart auf Verdacht.",
                        risk="Ein Neustart kann laufende Arbeit unterbrechen.",
                        permission="Administratorrechte für Dienständerungen.",
                        reversible=True,
                        automatable=False,
                    )
                )
            if total_ram > 0 and service.memory_bytes is not None and service.memory_bytes > total_ram * 0.35:
                recommendations.append(
                    Recommendation(
                        id=f"service-memory-{service.unit}",
                        severity="warning",
                        title=f"Hoher Speicheranteil: {service.unit}",
                        problem="Ein einzelner ShopOS-Dienst belegt mehr als 35 % des gesamten RAM.",
                        cause="Lastspitze, Cachewachstum oder ungeeignete Workergrenzen sind mögliche Ursachen.",
                        impact="Andere Dienste geraten schneller unter Speicherdruck.",
                        action="Verlauf und konkrete Dienstmetriken prüfen, bevor Limits verändert werden.",
                        expected_benefit="Gezieltes statt pauschales Ressourcen-Tuning.",
                        risk="Zu harte Limits können legitime Bestellspitzen ausbremsen.",
                        permission="Keine für Diagnose; Änderungen bestätigt.",
                        reversible=True,
                        automatable=False,
                    )
                )

        return recommendations
