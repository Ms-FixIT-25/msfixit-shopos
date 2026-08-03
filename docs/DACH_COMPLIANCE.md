# ShopOS 0.5 – Österreich- und DACH-Compliance

Stand der technischen und rechtlichen Quellenprüfung: 3. August 2026.

## Grundsatz

ShopOS ist ein technisches Kontroll- und Dokumentationssystem. Es kann Pflichtangaben erzwingen, ungeprüfte Märkte und Produkte sperren, Nachweise archivieren, Fristen sichtbar machen und Entscheidungen unveränderlich dokumentieren. Es ersetzt weder Rechtsberatung noch Steuerberatung und entscheidet keine strittigen Einzelfälle.

Das System arbeitet deshalb **fail closed**:

- Österreich, Deutschland und die Schweiz starten gesperrt;
- ein Markt wird erst nach freigegebenen Rechtstexten und Steuerprofilen aktiviert;
- ein Artikel wird je Markt separat freigegeben;
- Lieferanten- und Registrierungsangaben werden nicht aus Werbetexten abgeleitet;
- eine Rechnung wird ohne freigegebene Steuerentscheidung nicht final;
- strukturierte E-Rechnungen werden nicht vorgetäuscht;
- Schwellenüberschreitungen sperren riskante Steuerprofile bis zur Prüfung;
- bestehende Belege, Checkout-Nachweise und Audit-Ereignisse bleiben unveränderlich.

## Österreich

### Rechnung und Aufbewahrung

Die Rechnungserstellung prüft die nach § 11 UStG erforderlichen Stammdaten, Leistungsbeschreibung, Leistungszeitpunkt, Entgelt, Steuerbehandlung und Belegnummer. Bei Anwendung der österreichischen Kleinunternehmerbefreiung darf keine Umsatzsteuer ausgewiesen sein; ein unrichtiger Steuerausweis wird nicht automatisch toleriert.

Bücher, Aufzeichnungen und zugehörige Belege werden mindestens sieben Jahre aufbewahrt. Bei anhängigen Verfahren kann eine längere Aufbewahrung notwendig sein. ShopOS verkürzt eine vorhandene Aufbewahrungsfrist niemals und erlaubt einen nicht rücknehmbaren Legal Hold.

### Kleinunternehmerregelung

Der Kontrollwert für die österreichische Kleinunternehmerbefreiung beträgt derzeit 55.000 Euro. ShopOS führt zusätzlich den gesetzlichen 10-Prozent-Toleranzwert von 60.500 Euro. Der Zähler ist bewusst konservativ und dient als Sperre und Warnung; die umsatzsteuerliche Bemessung und einzelne nicht einzubeziehende Umsätze müssen steuerlich geprüft werden.

Warnstufen sollen bei 80 Prozent, 95 Prozent, Erreichen der Grenze und Erreichen des Toleranzwerts angezeigt werden. Oberhalb des Toleranzwerts erzeugt die Regel-Engine keine neue freigegebene Entscheidung `at_small_business_exempt`.

### EU-Kleinunternehmerbefreiung und OSS

Eine österreichische Kleinunternehmerbefreiung gilt nicht automatisch im Ausland. Für die grenzüberschreitende EU-Kleinunternehmerregelung sind unter anderem das besondere Antrags-/Identifikationsverfahren, die nationale Zielmarktgrenze und die unionsweite 100.000-Euro-Grenze zu beachten. Die zugehörige Registrierungsnummer und ihr Nachweis müssen je Zielmarkt gespeichert sein.

Für innergemeinschaftliche B2C-Fernverkäufe wird die unionsweite 10.000-Euro-Schwelle überwacht. Oberhalb dieser Schwelle verlangt ShopOS eine dokumentierte OSS-/Bestimmungslandbesteuerung oder eine wirksam nachgewiesene grenzüberschreitende Kleinunternehmerbefreiung.

### Fernabsatz und Widerruf

Für Verbraucherverträge im Fernabsatz wird grundsätzlich eine 14-tägige Widerrufsfrist abgebildet. Ausnahmen, insbesondere bei vollständig erbrachten Dienstleistungen oder digitalen Inhalten, werden nicht aus der Produktart erraten. Sie brauchen einen geprüften Ausnahme-Code sowie die jeweils erforderliche ausdrückliche Zustimmung und Kenntnisnahme.

Die elektronische Widerrufsfunktion wird zweistufig umgesetzt:

1. gut sichtbarer Einstieg `Vertrag widerrufen`;
2. Erfassung der Vertragsidentifikation und Erklärung;
3. Kontrollansicht;
4. ausdrücklicher Button `Widerruf bestätigen`;
5. unveränderlicher Zeitstempel und Inhalts-Hash;
6. unverzügliche Eingangsbestätigung auf dauerhaftem Datenträger.

Für Österreich ist die verpflichtende Online-Widerrufsfunktion mit dem vorgesehenen Wirksamkeitsdatum 1. Oktober 2026 im Marktprofil hinterlegt. ShopOS stellt sie bereits vorher bereit. Die Eingangsbestätigung ist keine automatische Anerkennung aller Anspruchsvoraussetzungen.

### Produktsicherheit, Verpackung, Elektro und Batterien

Für Angebote an EU-Verbraucher werden die GPSR-Angaben gespeichert und sichtbar ausgegeben:

- Herstellername;
- postalische Anschrift und E-Mail-Adresse;
- eindeutige Produktkennung;
- bei Hersteller außerhalb der EU die verantwortliche Person in der EU mit Anschrift und E-Mail;
- Warn- und Sicherheitsinformationen in verständlicher Sprache.

Bei Elektrogeräten, Batterien/Akkus und Verpackungen werden Rolle, Registrierung, Sammel-/Systemteilnahme und gegebenenfalls bevollmächtigte Person geprüft. Beim Direktversand durch einen Lieferanten wird der tatsächliche Versender separat dokumentiert. Ein bloßes Lieferantenversprechen ohne prüfbaren Nachweis genügt nicht.

## Deutschland

### Checkout

Der Bestellbutton lautet `Zahlungspflichtig bestellen`. Lieferbeschränkungen, akzeptierte Zahlungsmittel, Gesamtpreis, Versandkosten und die wesentlichen Vertragsinformationen müssen unmittelbar vor der Bestellung klar erkennbar sein. ShopOS speichert die am Checkout verwendete Button-Beschriftung, Preise, Zahlungsart, Lieferzusage, Produktfreigaben und Rechtstextversionen als unveränderlichen Snapshot.

### Elektronische Widerrufsfunktion

Für deutsche Verbraucherverträge stellt ShopOS die gesetzlich vorgesehene, ständig verfügbare elektronische Widerrufsfunktion bereit. Sie enthält einen ersten Aufruf `Vertrag widerrufen` und eine zweite ausdrückliche Bestätigung `Widerruf bestätigen`. Inhalt, Datum und Uhrzeit der Erklärung werden gespeichert und unverzüglich bestätigt.

### Verpackung und Dropshipping

Für Verkäufe nach Deutschland werden LUCID-Registrierung und Systembeteiligung geprüft. Beim Dropshipping ist zusätzlich der tatsächliche Versender zu erfassen. ShopOS akzeptiert entweder:

- nachgewiesene Registrierung/Systembeteiligung der Verkäuferin, soweit sie die Verpflichtete ist; oder
- eine geprüfte Lieferanten-/Versenderfreigabe mit Registrierungs- und Systemnachweis.

Die Datenbank ist auf eine spätere automatisierte Registerprüfung vorbereitet. Eine nicht geprüfte Zeichenfolge im Feld `LUCID` gilt nicht als Verifikation.

### Elektro- und Batterieprodukte

Ein Elektroartikel wird für Deutschland nicht freigegeben, solange die erforderliche Hersteller-/Bevollmächtigtenregistrierung beziehungsweise WEEE-Nummer fehlt. Entsprechendes gilt für Batterien und Akkus. Der tatsächliche Hersteller, Importeur oder ausländische Anbieter und dessen bevollmächtigte Person müssen entsprechend der Lieferkette erfasst werden.

### E-Rechnung

Eine normale PDF-Rechnung ist keine strukturierte E-Rechnung. ShopOS 0.5 erzeugt weiterhin menschlich lesbare PDFs und behauptet keine EN-16931-Konformität.

Die deutsche inländische B2B-E-Rechnungspflicht wird nicht pauschal auf jede Lieferung an ein deutsches Unternehmen angewendet. Die Entscheidung berücksichtigt insbesondere die tatsächliche Niederlassung der leistenden Unternehmerin, den Empfängertyp, Übergangsregelungen, Kleinunternehmerausnahmen und die konkrete Transaktion. Ist eine deutsche inländische B2B- oder öffentliche E-Rechnung erforderlich, blockiert ShopOS die Finalisierung, solange kein getesteter XRechnung-, ZUGFeRD- oder anderer zulässiger Strukturadapter eingerichtet ist.

Rechnungsdaten für einschlägige deutsche Sachverhalte werden mindestens acht Jahre aufbewahrt. Besteht gleichzeitig eine längere Markt- oder Verfahrensfrist, gilt die längere Frist.

## Schweiz

### Kein erfundenes Widerrufsrecht

Die Schweiz kennt für normale Internetkäufe kein allgemeines gesetzliches 14-Tage-Widerrufsrecht. Das Schweizer Marktprofil lautet daher `none_statutory`. Eine freiwillige Rückgabe- oder Widerrufsregel wird erst aktiviert, nachdem Umfang, Frist, Rücksendekosten, Ausnahmen und Rückzahlung ausdrücklich als Vertragsregel freigegeben wurden.

### Preise und Vertragsabschluss

Bei einem gezielt an Schweizer Konsumenten gerichteten Angebot werden Endpreise in CHF einschließlich zwingender Zuschläge verlangt. Separat anfallende Versandkosten müssen klar und rechtzeitig sichtbar sein. Für messbare Waren wird der Grundpreis gepflegt. Der Shop erläutert technische Vertragsschritte, ermöglicht Korrekturen und bestätigt die Bestellung unverzüglich elektronisch.

Solange keine belastbare CHF-Endpreisdarstellung vorhanden ist, bleibt der Schweizer Checkout gesperrt.

### Zoll und Einfuhr

Für Schweizer Sendungen werden mindestens Warenbeschreibung, HS-Code, Ursprungsland, Wert, Währung, Gewicht, Handels-/Proformarechnung und der geprüfte Incoterm verlangt. DAP/DDP, Verzollungsentgelt und Kostenträger werden nicht geraten. Fehlen Einfuhr- oder Preisangaben, wird kein Versandlabel automatisiert erzeugt.

### Aufbewahrung

Geschäftsbücher und Buchungsbelege werden für Schweizer Sachverhalte mindestens zehn Jahre lesbar, unverändert und mit nachvollziehbarem Audit Trail aufbewahrt. Eine elektronische Rechnung benötigt nicht zwingend eine digitale Signatur, sofern Herkunft, Integrität und Nachvollziehbarkeit anderweitig zuverlässig belegt sind.

## EU-Importe aus Drittländern

Seit 1. Juli 2026 ist die bisherige Zollbefreiung für Sendungen bis 150 Euro unionsrechtlich geändert. ShopOS führt für entsprechende Direktimport-/Dropshipping-Fälle eine Zoll- und Landed-Cost-Prüfung und den aktuellen temporären Kontrollwert von 3 Euro je Warenposition. Dieser Wert wird nicht blind als endgültige Abgabe verbucht; Anzahl der Positionen, Einfuhrverfahren, Plattformrolle, Befördererangaben und spätere unionsrechtliche Änderungen müssen im konkreten Fall geprüft werden.

## Rechtstext-Versionen

Rechtstexte werden je Land und Dokumentart versioniert:

- Impressum;
- AGB;
- Datenschutz;
- Widerruf;
- Versand;
- Zahlung;
- Gewährleistung/Rückgabe;
- Produktsicherheit.

Eine Freigabe speichert Inhaltshash, Version, Gültigkeitsbeginn, Freigabeperson und optional die PDF-Datei samt Hash. Ändert sich eine WordPress-Seite nach der Freigabe, blockiert der Checkout. Eine aktive freigegebene Version kann nur deaktiviert, nicht umgeschrieben oder gelöscht werden.

Die am Checkout geltenden Versionen werden in der Bestellung gespeichert. Dokumente, die auf dauerhaftem Datenträger bereitzustellen sind, können der Bestellbestätigung als geprüfte Dateien angehängt werden.

## Produktfreigabe je Markt

Preis und Lagerbestand allein reichen nicht zur Veröffentlichung. Jeder Artikel benötigt je Zielmarkt mindestens:

- permanente `MF-…`-Warennummer;
- Produkt-/Modellkennung;
- Hersteller- und Kontaktangaben;
- gegebenenfalls EU-verantwortliche Person;
- Sicherheits- und Warnhinweise;
- Anleitungssprachen;
- CE-Prüfstatus, sofern erforderlich;
- Elektro-/Batterieklassifikation und Registrierungsnachweise;
- Lieferzeitfenster;
- Lieferant und tatsächlicher Versender;
- Gewährleistungs-/Rückgabeeinordnung;
- dokumentierte Freigabe.

Artikel können in Österreich freigegeben und gleichzeitig in Deutschland oder der Schweiz gesperrt bleiben.

## Steuerentscheidungen

Für jede Rechnung oder Gutschrift wird eine eigene Steuerentscheidung gespeichert. Sie enthält:

- Niederlassungsstaat der Verkäuferin;
- Bestimmungsland;
- B2C/B2B-Einordnung;
- UID und Prüfstatus, falls relevant;
- verwendetes Steuerverfahren;
- Steuersatz;
- E-Rechnungsanforderung;
- Begründung;
- entscheidende Person oder Regelversion.

Eine freigegebene Steuerentscheidung ist unveränderlich. Eine Korrektur erfolgt durch eine neue Entscheidung und gegebenenfalls einen Korrekturbeleg, nicht durch Überschreiben der Vergangenheit.

## Aufbewahrung und Datenschutz

ShopOS verwendet je Beleg die längere gespeicherte DACH-Frist. Checkout-Nachweise werden auf das zur Beweisführung Erforderliche begrenzt. IP-Adressen werden nicht eigens in den Compliance-Snapshot übernommen. Widerrufs- und Bestelldaten dürfen nicht unbegrenzt als Marketingdaten weiterverwendet werden.

Löschkonzepte müssen zwischen handels-/steuerrechtlichen Aufbewahrungspflichten, Rechtsverteidigung, Gewährleistung und DSGVO-Löschansprüchen unterscheiden. Ein Legal Hold ist zu begründen und darf nicht als pauschale Daueraufbewahrung missbraucht werden.

## Freigabe vor Produktivbetrieb

Vor dem Öffnen eines Markts sind mindestens erforderlich:

1. geprüfte Unternehmens- und Steuerdaten;
2. freigegebene Rechtstextversionen mit unveränderten Live-Seiten;
3. Umsatzsteuer-/OSS-/EU-SME-Entscheidung;
4. Verpackungs-, Elektro- und Batterieregistrierungen beziehungsweise geprüfte Versendernachweise;
5. Produktfreigaben für jeden Zielmarkt;
6. geprüfte Lieferzeiten, Versandkosten und Rücksendeprozesse;
7. Test der Bestellbestätigung und Rechtstextanhänge;
8. Test der elektronischen Widerrufsfunktion;
9. Test von Rechnung, Gutschrift, Steuerentscheidung und Archiv;
10. Wiederherstellungstest des externen verschlüsselten Backups.

## Primäre Rechts- und Behördenquellen

Die Regeln wurden anhand der jeweils aktuellen amtlichen Fassungen und Behördeninformationen modelliert, insbesondere:

- österreichisches RIS: UStG, BAO, FAGG und KSchG;
- Unternehmensserviceportal Österreich und Bundesministerium für Finanzen;
- deutsche Gesetze im Internet: BGB, EGBGB, UStG, VerpackG und ElektroG;
- deutsches Bundesministerium der Finanzen;
- Zentrale Stelle Verpackungsregister und Stiftung ear;
- Europäische Union: GPSR, Verbraucherrechte, Mehrwertsteuer/OSS und Batterierecht;
- Schweizer SECO, Preisbekanntgabeverordnung und Geschäftsbücherverordnung.

Ändert sich eine Quelle, wird die entsprechende Regelversion nicht still überschrieben. Sie benötigt eine neue Prüfung, eine Migration und nachvollziehbare Freigabe.
