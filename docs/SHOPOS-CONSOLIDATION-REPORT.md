# ShopOS Consolidation Report

Status: **in progress**

Dieses Dokument wird während der Konsolidierung fortgeschrieben. Eine Klassifizierung als `superseded` bedeutet noch **nicht**, dass ein PR/Branch bereits geschlossen oder gelöscht werden darf. Das geschieht erst nach erfolgreicher Integration und Validierung des finalen Konsolidierungsstands.

## Ausgangslage

- Repository: `Ms-FixIT-25/msfixit-shopos`
- dokumentierter Ausgangscommit von `main`: `894c8c9f0fd285089dce9911d0327c7e1341a59c`
- Ausgangscommit-Nachricht: `Merge pull request #67 ... Fix release-assets workflow ShellCheck failure`
- Sicherheits-/Integrationsbranch: `integration/shopos-master-consolidation`
- historische Pull Requests erfasst: **73**
- Remote-Branches bei Erstinventur erfasst: **61** vor Erstellung des Integrationsbranches
- offene Production-Readiness-Issues: **5** (`#41`–`#45`)
- direkter lokaler `git clone` war in der Ausführungsumgebung wegen fehlender GitHub-DNS-Erreichbarkeit nicht möglich; Commit-, PR-, Branch-, Diff- und Dateivergleiche werden deshalb über die GitHub-API/Connector-Ebene durchgeführt. Diese Einschränkung wird bei jeder Aussage berücksichtigt, die normalerweise einen lokalen Arbeitsbaum voraussetzen würde.

## Aktive Production Gates

| Issue | Thema | Implementierungsstand | Evidence-Stand | Entscheidung |
|---|---|---|---|---|
| #41 | Signed transactional A/B updates and rollback | wesentlich teilweise implementiert | reale Power-loss-/Rollback-Matrix fehlt | offen lassen |
| #42 | Encrypted backup and bare-metal restore | lokales Backup vorhanden, Verschlüsselung/Restore unvollständig | echter Bare-metal-Restore fehlt | offen lassen |
| #43 | Runtime/network/admin hardening | viele Einzelgrenzen vorhanden | vollständiger systemd-/Port-/Bruteforce-Nachweis fehlt | offen lassen |
| #44 | Attestations, RootFS-SBOM, vulnerability gates | Provenienz/SBOM-Grundlage vorhanden | Attestation + vollständiger CVE-Gate fehlen | offen lassen |
| #45 | Physical hardware/power-loss/pilot lab | Hardware-Reporter/Testplan vorhanden | reale gebundene Hardware-Reports fehlen | offen lassen |

## Aktueller PR-Stack #66–#77

| PR | Rolle | bisheriger Befund | Konsolidierungsentscheidung |
|---|---|---|---|
| #66 | Produktfix Display/First Login | neuester tty/getty/consoleblank-Produktstand; Basis vieler Audit-Fixes | Produktlogik erhalten und gegen Masterbranch prüfen |
| #68 | Repository-Audit | audit-only, keine Produktfunktion; lieferte 0/0 Audit gegen späteren Stack | Auditlogik ggf. in dauerhafte PR-Validation übernehmen, Branch später schließen |
| #69 | Disposable QEMU Harness | ausdrücklich temporär; pinned altes Artefakt | nicht als Produktworkflow übernehmen; Evidence dokumentieren, später schließen |
| #70 | Nginx Security | stärker als #77: Upload/Files **und Hidden Paths** vor generischem PHP-Regex | stärkste Config + Regressionstest übernehmen |
| #71 | Signed App Installer | stärker als #77: paketierte Runtime, Identity-Binding, Special-Tar-/set-id-Rejection, Rollback-Test | stärkste Runtime + Test übernehmen |
| #72 | A/B Update Safety | stärker als #77: Manifest-Freshness, Lock, write-before-stage, abort-stage, Kapazitätscheck | vollständig übernehmen |
| #73 | Dual-host Repeat Harness | test-only/temporär, vier vollständige Boots | nicht dauerhaft als Produktpipeline; spezifische nützliche Assertions ggf. in normalen Gate übernehmen |
| #74 | Cloudflare Token | stärker als #77: RuntimeDirectory, Symlink-Schutz, token-file, `Restart=on-failure`, Rate Limit | stärkste Unit/Wrapper/Test übernehmen |
| #75 | Health Monitor | in #66-Stack gemergt; Compliance-Worker wird mit überwacht | Health-Fix + Test erhalten |
| #76 | Admin Credential Ownership | einzigartig: `msfixit-apply-config` darf Linux-Passwort nie ändern; Regression fehlt in #77 | gezielt übernehmen |
| #77 | gemeinsames Audit-Hardening | gute gemeinsame Basis für Release/Admin/Backup/Reproducibility, aber **kein Superset** #70–#76 | dateiweise übernehmen und mit stärkeren Einzel-Fixes überschreiben |

## Nachgewiesene Konflikte / verlorene Regressionen im späteren Stack

### PR #72 vs #77

Die #72-Version von `tests/test-shopos-update-agent.sh` prüft zusätzlich:

- timezone-aware `issued_at` / `expires_at`
- Ablehnung abgelaufener Manifeste
- Ablehnung zu weit zukünftiger Issue-Zeit
- `expires_at > issued_at`
- Slot-Write **vor** persistentem `stage`
- exklusives Update-Lock
- `abort-stage`
- Preflight-Zielkapazität und Ablehnung eines zu großen Images vor dem ersten Write

Die #77-Version prüft nur Repository-/URL-Trust-Boundaries. Damit ist #72 weiterhin produktrelevant.

### PR #71 vs #77

Die #71-Version testet die tatsächlich paketierte Runtime unter `/usr/lib/msfixit-shopos/` und bindet signierte App-ID/Version an das Manifest. Sie lehnt außerdem spezielle Tar-Member und set-id-Inhalte ab. #77 besitzt eine einfachere Runtime und einen älteren Testpfad. #71 bleibt deshalb Quelle für den finalen Installer.

### PR #70 vs #77

#77 setzt den Upload-PHP-Deny vor den generischen PHP-Handler, lässt aber den Hidden-Path-Deny **nach** dem generischen PHP-Regex stehen. #70 setzt beide Deny-Regeln vor die generische PHP-Ausführung und besitzt dafür einen Regressionstest. Die #70-Reihenfolge wird übernommen.

### PR #74 vs #77

#74 besitzt einen privaten systemd `RuntimeDirectory`, prüft die Token-Konfiguration gegen Symlinks, übergibt ausschließlich `--token-file` und verwendet `Restart=on-failure`. #77 besitzt zwar token-file, ist aber schwächer bei Unit/Runtime-Vertrag. #74 wird als stärkere Variante verwendet.

### PR #76 vs #77

#77 trennt bereits Control-Center- und Linux-Passwort, übernimmt aber den #76-Regressionsvertrag für `msfixit-apply-config` nicht. #76 wird deshalb gezielt integriert.

## Alte PR-Ketten – vorläufige Klassifizierung

### Plattform/Admin/UX #20, #23, #25–#39

Die später nach `main` gelangte Integration enthält heute die wesentlichen Produktbausteine aus:

- Admin Console
- Product GUI
- Guided Device Wizard
- Core/App Platform
- License Runtime
- App Catalog/Store
- Signed App Installer
- Install Helper
- Store Install Request
- UX Framework
- First-Boot OOBE

PR #39 beschreibt ausdrücklich die Fusion von #36/#37/#38; spätere `main`-Vergleiche zeigen die entsprechenden Plattform-/UX-/OOBE-Dateien und Tests. Die noch offenen historischen Draft-PRs werden dennoch erst nach vollständigem Masterbranch-Test geschlossen.

### Historische QEMU-Harnesses

PRs #17, #22, #28, #69 und #73 sind bzw. waren primär Validierungs-Harnesses. PR #61 hat bereits eine permanente exact-candidate ARM64-QEMU-Release-Gate-Architektur eingeführt und alte überlappende VM-Workflows entfernt. Historische Harnesses werden daher nicht blind in das Produkt übernommen.

## Hardware Manager

Branch `feature/shopos-hardware-manager` wurde gegen `main` verglichen.

Vorhanden sind bereits:

- Python-Service-Kern
- Plattformadapter für Raspberry Pi, allgemeines Linux und macOS
- Sensor-, State-, Rule- und Thermal-Module
- lokale API
- privilegierter Action-Helper
- systemd Service
- sudoers-Grenze
- Admin-GUI `hardware.php`
- Hardware-Manager-Dokumentation

Noch nicht als vollständig integriert nachgewiesen:

- Paket-/Postinst- und Service-Aktivierung im aktuellen Produktstand
- eindeutiger Control-Center-Navigationseintrag
- vollständige Tests/Fixtures für Pi/Linux/VM/macOS
- simulierte Thermal-, Undervoltage-, Storage-, USB- und Netzwerkfälle
- bewiesene Ressourcenobergrenze des Managers selbst
- sicherer, mehrfach bestätigter Notfall-Shutdown-Pfad
- Zusammenspiel mit bestehenden statischen Pi-Ressourcenbudgets

Daher wird der Branch **nicht blind gemergt**, sondern als Komponentenquelle verwendet.

## Dokumentationsdrift in `main`

Bereits nachgewiesen:

- `README.md` bezeichnet den Stand noch als `ShopOS 0.10`, obwohl spätere Releases/Versionierung existieren.
- README sagt „without ... a desktop“, obwohl ein lokaler X11/Chromium-Kiosk existiert; die Formulierung muss zwischen „kein vollständiger Desktop“ und „grafische Appliance“ unterscheiden.
- README führt A/B-Betriebssystemupdates noch als geplante Expansion, obwohl wesentliche A/B-Komponenten bereits implementiert sind.
- `docs/RELEASE_POLICY.md` beschreibt noch einen write-enabled automatischen Merge-Job; der aktuelle Release-Gate-Grundsatz seit PR #61 lautet ausdrücklich **kein Auto-Merge**.
- `docs/PRODUCTION_READINESS.md` markiert mehrere inzwischen teilweise implementierte A/B-/Rollback-/Health-/Release-Punkte noch pauschal als offen. Die Evidence-Gates selbst bleiben offen und dürfen nicht fälschlich abgehakt werden.

## Übernommene Änderungen

Noch keine Produktdatei wurde in diesem Report-Stand gelöscht. Der Integrationsbranch wurde zunächst absichtlich nur mit Anforderungs- und Evidence-Dokumentation begonnen.

## Entfernte Altlasten

Noch keine. Löschungen erfolgen erst nach Referenzprüfung und nachdem Ersatz + Regressionstest im Konsolidierungsbranch vorhanden sind.

## Tests

### Bereits aus vorherigem Audit belegt

Der unveränderte Full-Repo-Audit wurde gegen den damaligen #77-Merge-Stand ausgeführt:

- 172 klassifizierte Code-/Config-Ziele
- Errors: 0
- Warnings: 0
- Repository contract suite: PASS
- Workflow integrity: PASS
- First-boot storage permissions: PASS

Diese Evidence gilt **nur für den damaligen Audit-Stand** und wird nach der Master-Konsolidierung erneut ausgeführt. Sie ist kein Ersatz für das finale Image-/QEMU-Gate.

### Noch auszuführen

- finaler statischer Voll-Audit
- komplette Repository-/Contract-Suite
- Workflow-/YAML-/actionlint/ShellCheck
- PHP/Python-Syntax/Tests
- Security-Regressions #70/#71/#72/#74/#76
- Hardware-Manager Unit-/Fixture-Tests
- Package-Build
- Raspberry-Pi-4 Candidate Image Build
- SHA-256/Provenienz
- ARM64-QEMU-Boot exakt dieses Images

### Nicht als ausgeführt zu behaupten

- physischer Raspberry Pi Boot des Konsolidierungsimages
- realer HDMI-/Display-Retest des neuen First-Login-Stacks
- Stromausfalltests
- 72-Stunden-Soak
- Bare-metal Restore
- Pi5 Hardwarematrix
- reale Drucker-/Peripheriematrix

## Branch-/PR-Cleanup-Regel

Kein historischer PR oder Remote-Branch wird allein aufgrund dieser vorläufigen Klassifizierung geschlossen/gelöscht. Voraussetzungen sind:

1. einzigartige Produktänderungen und Regressionstests sind im Masterbranch nachweislich vorhanden,
2. finaler Branch ist statisch/funktional grün,
3. Image-Build und ARM64-QEMU-Systemtest sind grün,
4. PR ist dann dokumentiert superseded oder bewusst test-only,
5. kein aktiver Workflow hängt mehr vom Branch ab.

## Nächste Integrationsschritte

1. #77-Dateien konfliktbewusst auf aktuellem `main` übernehmen.
2. stärkere #70/#71/#72/#74/#76-Versionen darüber anwenden.
3. Hardware Manager vervollständigen und testen.
4. Workflows konsolidieren.
5. Dokumentationsdrift korrigieren.
6. Altlasten-/Referenzanalyse und erst danach Löschungen.
7. vollständige CI + frisches Image + ARM64-QEMU.
8. genau einen finalen Konsolidierungs-PR gegen `main` erstellen; kein Auto-Merge.
