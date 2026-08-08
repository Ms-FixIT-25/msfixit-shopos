# ShopOS Master Requirements

Stand der Konsolidierung: 2026-08-07

Ausgangsbasis: `main` bei `894c8c9f0fd285089dce9911d0327c7e1341a59c`.

Dieses Dokument ist der verbindliche Anforderungskatalog für die Repository-Konsolidierung. Es trennt **Produktanforderungen** von historischen Implementierungsdetails und temporären Test-Harnesses. Ein alter PR gilt nicht allein wegen Alter, Merge-Status oder einer späteren Integrationsbeschreibung als erledigt; entscheidend sind Produktcode, Regressionstests und der Vergleich gegen den konsolidierten Stand.

Statuswerte: `implemented`, `partially implemented`, `missing`, `obsolete`, `superseded`, `conflicting`, `test-only`, `documentation-only`.

| ID | Bereich | Anforderung | Quelle | Status | Implementierung | Test / Beweis | Entscheidung |
|---|---|---|---|---|---|---|---|
| CORE-001 | Produkt | ShopOS bleibt eine benutzerfreundliche Appliance-Plattform und kein bloßer Webserver. | Master-Konsolidierungsauftrag; PRs #25-#39 | partially implemented | Control Center, Kiosk, OOBE/UX-Bausteine | GUI-/OOBE-Vertragstests; reale UX weiter physisch prüfen | Erhalten und vereinheitlichen |
| CORE-002 | Produkt | Primäres Referenzziel ist Raspberry Pi 4; Pi 5 bleibt beworbener Architekturpfad, soweit tatsächlich validiert. | PR #5; README; Master-Konsolidierungsauftrag | implemented | rpi4/rpi5 Image-Targets | Image-Builds vorhanden; physische Matrix offen | Erhalten, Hardware-Support ehrlich dokumentieren |
| CORE-003 | Plattform | Allgemeines ARM64/Linux darf erkannt werden; hardwareabhängige Regeln dürfen nicht blind auf fremde Plattformen angewandt werden. | Master-Konsolidierungsauftrag; Hardware-Manager | partially implemented | Hardware-Manager-Plattformadapter im Feature-Branch | neue Unit-/Fixture-Tests erforderlich | In Hardware Manager vervollständigen |
| CORE-004 | Plattform | macOS-Unterstützung des Hardware Managers beschränkt sich auf sinnvolle Diagnose-/Managementfunktionen. | Master-Konsolidierungsauftrag; Hardware-Manager | partially implemented | macOS-Adapter vorhanden | nur simuliert/statisch prüfbar in aktueller CI | Als Capability-gated Support kennzeichnen |
| CORE-005 | Daten | Persistente Geschäftsdaten bleiben vom austauschbaren Root-System getrennt. | Issues #41/#42; PRs #46-#48 | implemented | `/data`, A/B Root-Slots | A/B-/Storage-Regressionstests | Erhalten |
| UX-001 | UX | Lokale grafische Appliance-Oberfläche startet auf angeschlossenem Display ohne vollständigen Desktop. | PR #56 | implemented | X11 + Chromium Kiosk | Source/QEMU; reale Anzeige separat | Erhalten |
| UX-002 | UX | GUI ist responsive für Desktop, Tablet und Mobile und benötigt keine Linux-Kenntnisse. | PRs #25-#38; Master-Konsolidierungsauftrag | partially implemented | Admin GUI, UX Framework, OOBE | PHP/UX-Vertragstests | Vereinheitlichen, keine parallelen Designwelten |
| UX-003 | UX | Assistenten liefern klare Schritte, verständliche Fehlertexte und sichere Defaults. | PRs #25/#26/#38 | implemented | Wizard/OOBE/Geräteassistent | Wizard-Tests | Erhalten |
| UX-004 | Display | `tty1` darf während Ersteinrichtung nicht automatisch blanken/DPMS-flackern. | reale Pi-Beobachtung; PRs #64-#66 | partially implemented | `consoleblank=0`, keepawake, dedizierter First-Login-Service im PR-Stack | statische/QEMU-Regressions; echter Pi-Retest nötig | neuesten #66-Stand integrieren |
| UX-005 | Display | Interaktiver First Login darf nicht als getty `ExecStartPre` mit normalem systemd-Timeout laufen. | PR #66 | implemented außerhalb main | dedizierter `msfixit-first-login.service`, `TimeoutStartSec=infinity` | First-login-Regressions | In Konsolidierung übernehmen |
| UX-006 | WLAN | First Login scannt Netze aktiv, fragt geschützte WLAN-Passwörter interaktiv und speichert keine WLAN-Secrets im Repo/Image. | PRs #24/#57/#66 | implemented | NetworkManager-Flow | `test-first-login-wifi.sh` | Erhalten |
| AUTH-001 | Admin | Linux-/SSH-Administratorpasswort hat genau einen Besitzer: interaktiver First Login. | PR #76; Audit | implemented außerhalb main | First-login `chpasswd`; unattended firstboot/apply-config dürfen es nicht ändern | `test-shopos-admin-credential-ownership.sh` | stärkeren #76-Vertrag integrieren |
| AUTH-002 | Admin | Control-Center-Passwort ist vom Linux-Login getrennt. | PR #77 | implemented außerhalb main | `CONTROL_ADMIN_PASSWORD` / `control-console.env` | Audit-Hardening | Integrieren |
| AUTH-003 | Admin | Admin-Sessions rotieren bei Login und verwenden sichere Cookie-Attribute. | PRs #20/#23/#25; Issue #43 | implemented | PHP Session-Handling | Admin-Konsole-Tests | Erhalten |
| AUTH-004 | Admin | Zustandsändernde Webaktionen benötigen CSRF-Schutz und explizite Bestätigung. | PRs #23/#25/#35/#38/#50 | implemented | Admin/Store/OOBE/Update Center | Contract-Tests | Erhalten |
| AUTH-005 | Admin | Keine freie Shell-, URL- oder Pfadübergabe aus dem Browser an privilegierte Prozesse. | Security; PRs #26/#34/#35/#50; Issue #43 | implemented/ongoing | Allowlist-Helper; argv-basiertes `proc_open` | Security-/Audit-Tests | weiter verschärfen |
| ADMIN-001 | Admin | Control Center zeigt Systemzustand, Dienste, Speicher, Temperatur, Laufzeit und Backups verständlich. | PRs #20/#23/#25 | implemented | Admin GUI | Admin-Tests | Erhalten; Hardware-Daten später zentralisieren |
| ADMIN-002 | Admin | Begrenzte Wartungsaktionen: Backup, Cache, allowlistete Dienstneustarts und redigierte Logs. | PR #23 | implemented | `msfixit-admin-action` | Admin Phase-2 Tests | Erhalten |
| ADMIN-003 | Admin | Privilegierte GUI-Prozesse verwenden argv-basiertes `proc_open` ohne Shell und harte Zeitlimits. | Audit/PR #77 | implemented außerhalb main | Admin/Update PHP | `test-shopos-audit-hardening.sh` | Integrieren |
| DEV-001 | Geräte | Wechselmedien werden erkannt, aber niemals unbekannt automatisch beschreibbar gemountet. | PR #26; Master-Konsolidierungsauftrag | implemented | Device queue + Guided Wizard | `test-guided-device-wizard.sh` | Erhalten |
| DEV-002 | Geräte | Mounts verwenden mindestens `nosuid,nodev,noexec`, optional `ro`, und validieren Gerät unmittelbar vorher erneut. | PR #26; Issue #43 | implemented | enger Admin-Helper | Device-Wizard-Tests | Erhalten |
| APP-001 | Plattform | Core und Apps sind getrennt; Apps dürfen Core-Dateien nicht überschreiben. | PR #27; `SHOPOS_PLATFORM.md` | implemented contract | Manifest/Plattformvertrag | Plattform-Core-Test | Erhalten |
| APP-002 | Plattform | App-Manifeste sind streng versioniert, unbekannte Felder und gefährliche Fähigkeiten werden fail-closed abgelehnt. | PR #27 | implemented | Validator/Schema | `test-shopos-platform-core.sh` | Erhalten |
| APP-003 | Lizenz | Community/Professional/Enterprise und Entwicklerentitlement verwenden signierte Lizenzdokumente ohne Master-Bypass. | PR #30 | implemented | Ed25519 Lizenzruntime | Lizenztests | Erhalten |
| APP-004 | Store | App-Katalog/Store zeigt Lizenz-/Entitlementstatus fail-closed. | PRs #31/#32 | implemented | Katalog + Store GUI | Store-/Catalog-Tests | Erhalten |
| APP-005 | Installer | App-Pakete werden vor Installation mit Ed25519 + SHA-256 + strengem Manifest geprüft. | PRs #33/#71 | partially implemented in main; stronger fix outside | signierter Installer | stronger #71 regression | stärkere #71-Version integrieren |
| APP-006 | Installer | Signierte `app_id` und `version` müssen exakt mit dem gehashten Manifest übereinstimmen. | PR #71 | missing in current consolidated base | gehärteter Installer #71 | #71 Test | Integrieren |
| APP-007 | Installer | Tar-Links, Devices, FIFOs, Path Traversal und setuid/setgid-Inhalte werden vor Extraktion abgelehnt. | PR #71 | missing/partial | gehärteter Installer #71 | #71 Test | Integrieren |
| APP-008 | Installer | App-Installation ist transaktional und stellt vorherigen Stand bei Fehler wieder her. | PRs #33/#71 | implemented | Staging/Rollback | Installer-Test | Erhalten |
| APP-009 | Privilege | Store darf nur den engen App-Install-Helper mit validierter App-ID auslösen. | PRs #34/#35 | implemented | sudoers + Helper | Helper/Store-Request Tests | Erhalten |
| UPDATE-001 | Update | Systemupdate verwendet signiertes Manifest, Image-Größe, SHA-256, Ziel und Sequenz. | PRs #46/#50; Issue #41 | implemented/partial | Update-State-Machine + Agent | A/B/Agent Tests | Erhalten und härten |
| UPDATE-002 | Update | Replay und Downgrade werden fail-closed verhindert. | PR #46; Issue #41 | implemented/partial | Sequenz/Minimum | A/B-Tests | Erhalten; Production Gate bleibt offen |
| UPDATE-003 | Update | Update-Manifest hat timezone-aware `issued_at`/`expires_at`; abgelaufene oder zu weit zukünftige Manifeste werden abgelehnt. | PR #72 | missing in #77/current main | gehärtete Update Runtime | stronger #72 Agent-Test | Integrieren |
| UPDATE-004 | Update | Inaktiver Slot wird vollständig geschrieben/verifiziert, bevor persistenter `staged`-Zustand eröffnet wird. | PR #72 | missing in #77/current main | Agent-Reihenfolge | stronger #72 Agent-Test | Integrieren |
| UPDATE-005 | Update | Update-Apply ist exklusiv gesperrt; recoverable Staging-Fehler besitzen `abort-stage`. | PR #72 | missing in #77/current main | flock + State cleanup | #72 Agent-Test | Integrieren |
| UPDATE-006 | Update | Zielpartition wird vor dem ersten Write auf ausreichende Kapazität geprüft. | PR #72 | missing in #77/current main | BLKGETSIZE64/Testmodus | #72 Agent-Test | Integrieren |
| UPDATE-007 | Update | A/B Root A/B, Trial-Boot, Health-Bestätigung und automatischer Rollback bleiben vorhanden. | PRs #46-#48/#50; Issue #41 | partially implemented | physisches A/B Layout + Boot selector | automatisierte Tests/QEMU; Power-loss real offen | Issue #41 offen halten |
| UPDATE-008 | Update | `consoleblank=0` bleibt auch bei A/B Slot-Wechsel erhalten. | PRs #65/#66 | implemented outside main | Boot selector/postprocess | Display/A-B Regression | Integrieren |
| UPDATE-009 | Update | Update Center zeigt Slot/Status und startet System-/App-Updates über enge Helper. | PR #50 | implemented | `/admin/updates` | Update-Center-Test | Erhalten |
| NGINX-001 | Web | PHP in schreibbaren Upload-/Files-Bereichen wird vor generischem PHP-FPM-Regex blockiert. | PR #70; Audit | missing in main | Nginx deny ordering | #70 Nginx-Test | stärkste #70-Konfiguration integrieren |
| NGINX-002 | Web | Hidden-Path-Deny steht ebenfalls vor generischer PHP-Regex. | PR #70 | missing in #77 variant | Nginx location ordering | #70 Nginx-Test | #70 statt #77 verwenden |
| CF-001 | Cloudflare | Tunnel-Token darf niemals in Prozessargumenten oder allgemeiner Service-Environment erscheinen. | PR #74; Audit | missing in main | token file wrapper | #74 Cloudflare-Test | Integrieren |
| CF-002 | Cloudflare | Runtime-Token liegt nur root-lesbar unter privatem `/run`-Verzeichnis; unsichere/symlinked Konfiguration wird abgelehnt. | PR #74 | missing in #77 variant teilweise | wrapper + RuntimeDirectory | #74 Test | stärkste #74-Version verwenden |
| CF-003 | Cloudflare | Cloudflared nutzt `Restart=on-failure` und explizites Start-Rate-Limit statt Endlosschleife. | PR #74 | missing in #77 variant | systemd Unit | #74 Test | Integrieren |
| BACKUP-001 | Backup | Lokale Backups sichern relevante DBs, WordPress, Office/Partnerdaten und ShopOS-Konfiguration konsistent. | bestehender Backup-Code; Issue #42 | partially implemented | `msfixit-backup` | Contract/Audit | Erhalten |
| BACKUP-002 | Backup | Manuelle/geplante Backups verwenden konsistent `.tar.zst`; Dashboard erkennt dasselbe Format. | Audit/PR #77 | implemented outside main | zstd Backup | Audit-Hardening-Test | Integrieren |
| BACKUP-003 | Backup | Verschlüsselte lokale und externe/off-device Backups mit Schlüsseltrennung/Rotation. | Issue #42 | missing | — | Hardware/Restore Gate | neu implementieren, Issue offen |
| BACKUP-004 | Restore | Bare-metal Restore auf leere Ersatzhardware wird mit Hash/Commit protokolliert und manipulierte Backups fail-closed abgelehnt. | Issue #42 | missing | — | realer Restore erforderlich | Production Gate offen |
| HW-001 | Hardware Manager | Eigenständiger Hintergrund-Service plus GUI im Control Center. | Master-Konsolidierungsauftrag; `feature/shopos-hardware-manager` | partially implemented | Daemon/API/GUI im Feature-Branch | noch keine vollständige Paket-/GUI-/CI-Integration | vervollständigen |
| HW-002 | Hardware Manager | Plattform erkennen: Pi-Modell, CPU, Architektur, RAM, Kernel, Distribution/OS, VM, Storage, Filesystem. | Master-Konsolidierungsauftrag | partially implemented | Plattform-/Sensoradapter | Fixtures/Unit-Tests fehlen | vervollständigen |
| HW-003 | Hardware Manager | CPU/SoC-Temperatur, Verlauf und Thermal-Throttling/Undervoltage erfassen. | Master-Konsolidierungsauftrag; Pi-Thermal-Historie | partially implemented | thermal/sensors Module | simulierte Sensorfälle erforderlich | vervollständigen |
| HW-004 | Hardware Manager | Mehrstufige Thermalreaktion: Info → Warnung → kritisch → Schutzmaßnahme → Shutdown nur bestätigter Notfall. | Master-Konsolidierungsauftrag | partially implemented | Regel-/Thermalmodell | Shutdown zunächst fail-safe und simuliert testen | keine unnötigen Abschaltungen |
| HW-005 | Hardware Manager | CPU/RAM/Swap/I/O/Webstack/MariaDB/Redis/PHP-FPM/Chromium/Hintergrunddienste bewerten. | Master-Konsolidierungsauftrag; PR #58/#60 | partially implemented | statische Pi-Budgets + Manager-Sensorik | Resource-Budget + neue Manager-Tests | hardwareabhängig vereinheitlichen |
| HW-006 | Hardware Manager | Keine Standard-Übertaktung oder Spannungsanhebung; keine aggressive Daueruntertaktung. | Master-Konsolidierungsauftrag; PR #58 | implemented policy | konservative Budgets | Policy-Test ergänzen | beibehalten |
| HW-007 | Hardware Manager | Netzwerk zeigt Interface, Link-Speed, WLAN-Signal, Duplex, MTU und offensichtliche Fehlkonfigurationen. | Master-Konsolidierungsauftrag | partially implemented | Sensorik im Feature-Branch | Fixture-Tests fehlen | integrieren |
| HW-008 | Hardware Manager | USB, Datenträger, Drucker, Netzwerkadapter und relevante Peripherie erkennen. | Master-Konsolidierungsauftrag | partially implemented | Sensorik/Device Wizard | Device/Fixture Tests | integrieren ohne Automount |
| HW-009 | Hardware Manager | Monitoring selbst bleibt leichtgewichtig und erzeugt keine unnötige CPU-/I/O-/Flash-Last. | Hardware-Manager-Konzept; PR #58 | partially implemented | Sampling/State-Modell | Ressourcenvertrag ergänzen | beibehalten |
| PERF-001 | Raspberry Pi | Kiosk, PHP-FPM, Redis und MariaDB erhalten Pi-taugliche Ressourcenbudgets. | PRs #58/#60/#61 | implemented | resource budget service/finalizer | `test-pi-resource-budget.sh` | mit Hardware Manager abstimmen, nicht doppeln |
| PERF-002 | Raspberry Pi | Thermal-Monitoring darf keine künstliche Dauerlast erzeugen. | PR #58 | implemented | Timer statt busy polling | Resource-Test | Erhalten |
| RELEASE-001 | CI | PR-Validierung prüft statisch/funktional ohne Schreibrechte und ohne automatischen Merge. | PR #61; Master-Konsolidierungsauftrag | partially implemented | mehrere Workflows | Workflow-Integrity | Workflows konsolidieren |
| RELEASE-002 | CI | Candidate Image wird frisch aus exakt geprüftem PR-Stand gebaut und mit SHA-256/Metadaten versehen. | PRs #40/#61 | implemented | release gate | candidate build | Erhalten |
| RELEASE-003 | CI | Systemvalidierung bootet exakt dieses Candidate-Artefakt; keine hart codierte alte Artifact-ID. | PR #61 | implemented | ARM64-QEMU gate | QEMU evidence | Erhalten |
| RELEASE-004 | CI | Produktionsimage wird nach Merge erneut aus exaktem `main`-Commit gebaut. | PR #40 | implemented | production workflow | Production build | Erhalten |
| RELEASE-005 | CI | Stabiles GitHub Release wird erst nach erfolgreichem Production-Test, Image-Build und ARM64-QEMU-Boot veröffentlicht. | Audit/PR #77 | missing in main | gehärteter Production Release | neu end-to-end testen | Integrieren |
| RELEASE-006 | CI | Es gibt keinen zweiten automatischen parallelen Veröffentlichungsweg. | Master-Konsolidierungsauftrag; PR #77 | conflicting in main | build-image + asset sync historisch | Workflow-Audit | auf einen autoritativen Release-Pfad reduzieren |
| RELEASE-007 | CI | Release-Version steigt eindeutig und Dateinamen enthalten Version + Zielplattform. | PRs #62/#63 | implemented | Version-/Asset-Skripte | Release-Version/Asset Tests | Erhalten |
| RELEASE-008 | Supply Chain | WooCommerce-Archiv ist auf erwarteten SHA-256 gepinnt. | Audit/PR #77 | missing in main | vendor fetch | Audit-Hardening | Integrieren |
| RELEASE-009 | Reproduzierbarkeit | Paketmetadaten/mtimes nutzen `SOURCE_DATE_EPOCH` statt Runner-Wanduhr. | Audit/PR #77 | missing in main | build-package | Audit-Hardening | Integrieren |
| RELEASE-010 | CI | Temporäre QEMU-/Audit-Harnesses dürfen nicht als dauerhafte Produktpipeline verbleiben. | PRs #17/#22/#28/#68/#69/#73; Master-Konsolidierungsauftrag | conflicting | historische Harnesses/Branches | Branch-/Workflow-Inventur | klassifizieren, nach Beweis schließen/löschen |
| SEC-001 | Security | Fail-closed bei Identität, Lizenz, Entitlement, Signatur, Hash und sicherheitsrelevanter Konfiguration. | SECURITY.md; Master-Konsolidierungsauftrag | implemented/ongoing | mehrere Komponenten | Security Contract Suite | niemals fürs Cleanup abschwächen |
| SEC-002 | Security | Keine privaten Signing Keys, Master-Keys oder Universal-Bypässe im Repository/Image. | SECURITY.md; App/Lizenz-PRs | implemented | Public-key-only | secret/audit tests | Erhalten |
| SEC-003 | Security | CSP, Clickjacking-/MIME-Schutz, sichere Cookies, CSRF und Session-Rotation bleiben aktiv. | Admin/Store/OOBE PRs; Issue #43 | implemented | PHP Headers/Sessions | Admin tests | Erhalten |
| SEC-004 | Security | Logs/Diagnosen redigieren Tokens, Passwörter, API-Keys und unnötige Kundendaten. | PR #23; Issue #43 | partially implemented | admin log redaction | negative tests ausbauen | Issue #43 offen |
| SEC-005 | Security | systemd Units und sudoers folgen Least Privilege, keine `NOPASSWD: ALL`. | SECURITY.md; Issue #43; Audit | partially implemented | enge Helper + einzelne Sandboxen | Audit | vollständigen Unit-Review dokumentieren |
| SEC-006 | Security | SSH standardmäßig aus oder explizit key-only; Netzwerk-/Portmatrix dokumentiert. | Issue #43 | missing/partial | — | Netzwerk-/Runtime-Test | Production Gate offen |
| SEC-007 | Security | Brute-Force/Flood-Rate-Limits für Admin/OOBE/Public Endpoints. | Issue #43 | partially implemented | einzelne Rate Limits | systematische Negativtests fehlen | Production Gate offen |
| SBOM-001 | Supply Chain | GitHub Actions auf immutable Commit-SHAs pinnen. | Issue #44 | missing | derzeit Major-Tags wie `@v7` | workflow scan | Production Gate offen |
| SBOM-002 | Supply Chain | Vollständige RootFS-SBOM + CVE-Scan + blockierende Severity Policy. | Issue #44 | missing | nur SBOM-Grundlage | CVE Gate fehlt | Production Gate offen |
| SBOM-003 | Supply Chain | Release-Artefakt, SBOM, Provenienz und Quellcommit kryptografisch attestieren. | Issue #44 | missing | Provenienz vorhanden, Signatur fehlt | unabhängige Verifikation nötig | Production Gate offen |
| TEST-001 | Testing | Historische Regressionstests für reale Bugs bleiben erhalten, auch wenn Feature-Workflows konsolidiert werden. | Master-Konsolidierungsauftrag | partially implemented | viele Tests | `make check` | Tests behalten, Workflowduplikate reduzieren |
| TEST-002 | Testing | Static/Unit/Integration/QEMU/ARM64-QEMU/real Pi werden klar unterschieden. | Master-Konsolidierungsauftrag | implemented policy | Dokumentation/Reports | Hardware reporter | Beweissprache strikt beibehalten |
| TEST-003 | Testing | Physische Pi-/Power-loss-/Peripheral-Tests werden nie simuliert oder behauptet. | Issue #45; Master-Konsolidierungsauftrag | missing as evidence | Hardware validation harness vorhanden | echte Reports fehlen | Issue #45 offen |
| TEST-004 | Hardware Lab | Exaktes Release-Image wird mit Hardwaremodell, Commit und Image-SHA gebunden protokolliert. | PR #49; Issue #45 | implemented harness only | Hardware report script | echter Laborlauf fehlt | Harness behalten, Evidence offen |
| TEST-005 | Hardware Lab | Pi4 USB-SSD: cold boot, reboot, 72h soak, Stromausfälle, disk-full, DNS/Netz/Zeitfehler. | Issue #45 | missing | Testplan vorhanden | reale Hardware nötig | Production Gate offen |
| TEST-006 | Hardware Lab | Pi5 wird für alle tatsächlich beworbenen Storage-Ziele physisch geprüft. | Issue #45 | missing | Build Targets vorhanden | reale Hardware nötig | keine Werbung als validiert ohne Evidence |
| COM-001 | Commerce | Canonical article master mit unveränderlichen `MF-...`-Nummern und Integrations-Mappings. | PR #9 | implemented | Catalog DB | Catalog tests | Erhalten |
| COM-002 | Commerce | Österreich-Pilot bleibt fail-closed: Produkte/Preise/Publikation/Supplier Order manuell freigeben. | PR #12 | implemented | Pilot/ALSO Guards | ALSO tests | Erhalten |
| COM-003 | Commerce | ALSO kommerzieller Feed und lizenzierter Content sind getrennte, evidence-gated Datenströme. | PRs #12/#14 | implemented | ALSO modules | MariaDB/connector tests | Erhalten |
| COM-004 | Commerce | DACH Legal/Tax/Product-Safety-Kernel blockiert nicht freigegebene Märkte/Fälle. | PR #11 | implemented | Compliance DB/guards | Compliance tests | Erhalten; kein Rechtsversprechen ableiten |
| COM-005 | Office | Rechnungen/Belege/Zahlungen/Allokationen und relevante Auditdaten sind nach Finalisierung unveränderlich. | PR #10/#11 | implemented | Office DB guards | MariaDB tests | Erhalten |
| COM-006 | Health | Alle von Office Init aktivierten Worker-Timer einschließlich Compliance-Worker müssen im Health-Status überwacht werden. | PR #75 | implemented outside main | `msfixit-health` | `test-shopos-health-contract.sh` | Integrieren |
| HELP-001 | Support | Help Center, Service Requests und evidence-basierte Partnerprofile bleiben erhalten. | PRs #15/#16 | implemented | WordPress modules/partner DB | vorhandene Tests | Erhalten |
| DOC-001 | Dokumentation | README beschreibt den echten aktuellen Stand, keine alte Version 0.10 und keine bereits implementierten Features als „planned“. | aktuelles README vs PRs #46-#64 | conflicting | README veraltet | manueller Cross-Check | Aktualisieren |
| DOC-002 | Dokumentation | Release Policy darf keinen automatischen PR-Merge behaupten, wenn die aktuelle Policy keinen Auto-Merge erlaubt. | aktuelle `RELEASE_POLICY.md`; PR #61 | conflicting | Dokument veraltet | Workflowvergleich | Aktualisieren |
| DOC-003 | Dokumentation | Production Readiness bildet teilweise implementierte A/B-/Health-/Release-Funktionen differenziert ab, schließt Hardware-Gates aber nicht ohne Evidence. | `PRODUCTION_READINESS.md`; Issues #41-#45 | conflicting/partial | Checkliste veraltet | Issue-/Codevergleich | Aktualisieren |
| HYGIENE-001 | Repository | Keine IMG/ZIP/XZ/Logs/Buildausgaben/Secrets/IDE-/Cache-Dateien im Git-Index. | Master-Konsolidierungsauftrag | to verify | `.gitignore`/Indexprüfung | finaler Hygiene-Check | vor Final-PR beweisen |
| HYGIENE-002 | Repository | Alte PRs/Branches erst schließen/löschen, wenn keine einzigartige Änderung/Test mehr existiert und Konsolidierungsstand grün ist. | Master-Konsolidierungsauftrag | active policy | Konsolidierungsreport | PR/Branch-Vergleiche | strikt einhalten |

## Aktive Production Gates

Die Issues `#41` bis `#45` bleiben unabhängig vom aktuellen Implementierungsgrad offen, bis ihre **Abnahmeevidenz** vollständig vorliegt. Insbesondere ersetzt ein QEMU-Boot keinen Stromausfall-, Restore-, Peripheral- oder 72-Stunden-Test auf realer Hardware.

## Konflikte, die die Konsolidierung bereits nachgewiesen hat

1. PR #77 ist **kein vollständiger Superset** der Einzel-Fixes #70–#76.
2. PR #72 enthält stärkere Update-Freshness-, Locking-, Staging- und Kapazitätsregressionen als #77.
3. PR #71 enthält eine stärkere paketierte App-Installer-Laufzeit und stärkere Archiv-/Identity-Tests als #77.
4. PR #76 enthält den fehlenden Vertrag, dass `msfixit-apply-config` niemals das Linux-Login-Passwort ändert.
5. PR #70 schützt zusätzlich Hidden-Paths vor dem generischen PHP-Regex; die #77-Nginx-Variante ordnet diesen Deny zu spät ein.
6. PR #74 besitzt die stärkere Cloudflare-Systemd-/RuntimeDirectory-/Symlink-Schutzvariante.
7. README, Release Policy und Production Readiness auf `main` beschreiben teilweise einen älteren Produkt-/CI-Stand.

Diese Konflikte werden im Integrationsbranch explizit aufgelöst; keine der stärkeren Sicherheitsregressionen wird verworfen.
