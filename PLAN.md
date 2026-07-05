# RemPush Implementierungsplan

## Zielbild
RemPush ist eine iOS-App für genau neun farblich unterschiedliche Notizseiten. Jede Seite besteht nur aus Titel und Body, erhält beim ersten Speichern einen unveränderlichen Erstellungszeitpunkt und bleibt erhalten, bis der Nutzer sie explizit löscht. Beim Start öffnet die App die erste leere Seite; wenn alle Seiten befüllt sind, öffnet sie die zuletzt verwendete Seite und zeigt einen kurzen, automatisch verblassenden Hinweis. Nach Erstellung einer Seite kann ihr Titel als lokale Push-Benachrichtigung angezeigt werden. Am Monatsende werden alle in diesem Monat erstellten Notizen chronologisch als Textdatei an einen vom Nutzer konfigurierten Speicherort exportiert. Die offenen Seiten sollen über iCloud synchronisiert werden; Konflikte werden verlustfrei als Diff angezeigt und vom Nutzer entschieden.

## Red-Green-TDD Vorgehen
1. **Red:** Tests für die Kernregeln schreiben: neun Slots, Startseite, unveränderlicher `createdAt`, explizites Löschen, Monatsarchiv, Push-Anforderung und konfliktfreie bzw. konfliktbehaftete Synchronisation.
2. **Green:** Eine plattformunabhängige Core-Schicht implementieren, die unter Linux im CI mit `swift test` ausführbar ist.
3. **Refactor:** iOS-spezifische Adapter dünn halten: SwiftUI-Views, `UserNotifications`, Datei-/Security-Scoped-Bookmark-Auswahl und später CloudKit/NSUbiquitousKeyValueStore.

## Architektur
### RemPushCore
- `NotePage`: persistierbares Modell für einen der neun Slots.
- `NoteStore`: verwaltet Slots, zuletzt verwendeten Slot, Erstellen/Aktualisieren/Löschen und Startlogik.
- `MonthlyExporter`: erzeugt chronologische Monats-Textarchive und schreibt sie über eine injizierte Storage-Schnittstelle.
- `NotificationScheduling`: Protokoll für lokale Push-Benachrichtigungen; iOS-Implementierung nutzt `UNUserNotificationCenter`.
- `SyncEngine`: verarbeitet Remote-Versionen, erkennt Konflikte über Änderungsrevisionen, erzeugt ein Diff und hält beide Versionen bis zur Nutzerentscheidung vor.

### RemPushApp (iOS)
- `RemPushApp`: Einstiegspunkt.
- `AppViewModel`: bindet `NoteStore` an SwiftUI und orchestriert Toasts, Export und Push.
- `ContentView`: `TabView` im `.page`-Stil für horizontales Wischen durch neun Seiten; Titel- und Body-Eingabe per `TextField`/`TextEditor`, dadurch funktioniert iOS-Diktat in der Systemtastatur sofort und die Eingabe kann anschließend per Tastatur bearbeitet werden.
- Einstellungen enthalten einen Button für den Exportordner. In dieser Basisversion ist ein Core-Adapter vorbereitet; in einem Xcode-Projekt wird dieser mit `UIDocumentPickerViewController`/Security-Scoped Bookmarks verdrahtet.

## Datenverlust-Vermeidung
- Eine befüllte Seite wird nie automatisch entfernt; nur `deletePage` leert einen Slot.
- `createdAt` wird nur beim ersten Erstellen gesetzt und bei späteren Änderungen nicht verändert.
- Synchronisationskonflikte überschreiben nicht automatisch. `SyncEngine` liefert ein `SyncConflict` mit lokaler und entfernter Version sowie Diff. Erst `resolveConflict` übernimmt eine Version.
- Monatsarchive werden aus persistierten Seiten generiert und chronologisch sortiert.

## Basisversion in diesem Durchgang
- Swift Package mit ausführbaren Core-Tests.
- SwiftUI-App-Code, der auf iOS kompiliert und die geforderten UI-Elemente skizziert/abbildet.
- Mockbare Push-, Export- und Sync-Schichten.
- Dokumentierte Anschlussstellen für echtes iCloud/CloudKit, Ordnerauswahl und produktive Monatsend-Automation.

## Fortschritt: Basisversion 2
- Persistenz ist jetzt als `RemPushSnapshot` mit JSON-Dateiadapter modelliert; die App speichert nach jeder Änderung, damit Notizen nicht durch App-Neustarts verloren gehen.
- Einstellungen enthalten den Archivpfad und den zuletzt exportierten Monat. Der Monatsend-Export wird durch `MonthlyExportService` idempotent ausgelöst und schreibt `RemPush-YYYY-MM.txt` in den konfigurierten Ordner.
- Sync ist auf Snapshot-Ebene vorbereitet: konfliktfreie Remote-Änderungen werden übernommen; gleichzeitige Änderungen liefern `SyncConflict`-Objekte mit Diff, die in der GUI als Entscheidungssheet angezeigt werden.
- Die GUI wurde auf geringe Latenz und Minimalismus ausgerichtet: direkte lokale Speicherung, schlanke Seitenkarten, fokussierter Editor, dezente Farben, nicht blockierende Toasts und nur zwei primäre Aktionen pro Seite (Push, Löschen).

## Noch offene produktive Adapterarbeit
- Echte iCloud-Anbindung sollte den vorhandenen Snapshot über CloudKit oder ubiquitäre Dokumente transportieren und `applyRemoteSnapshot(_:)` bei Änderungen aufrufen.
- Die iOS-Ordnerauswahl sollte den derzeitigen Pfad-Textfeld-Prototyp durch `UIDocumentPickerViewController` samt Security-Scoped Bookmark ersetzen.
- Für App-Store-Auslieferung ist ein Xcode-Projekt bzw. eine XcodeGen/Tuist-Konfiguration mit Capabilities für iCloud und Push-Benachrichtigungen zu ergänzen.

## Fortschritt: Basisversion 3
- Toasts werden jetzt zentral im ViewModel animiert angezeigt und per nachrichtengebundener Task nach wenigen Sekunden wieder ausgeblendet, damit neue Hinweise alte Ausblend-Timer nicht blockieren.
- Nach dem Löschen synchronisiert die Seitenansicht ihren lokalen Editor-State explizit mit dem geleerten Store-Modell, sodass Titel und Inhalt sofort aus der UI verschwinden und nicht erst nach einem App-Neustart.
- Der iOS-Push-Adapter prüft vorhandene Berechtigungen, fordert Alert/Sound/Badge-Rechte an, behandelt verweigerte Berechtigungen als Fehler und plant lokale Titel-Benachrichtigungen mit Sound und stabilem RemPush-Identifier-Präfix.
- Jede der neun Seiten nutzt nun ihre eigene Akzentfarbe für Hintergrund, Eingaberahmen, Header-Chip und Bedienelement-Tint.

## Fortschritt: Basisversion 4
- Die Push-Erzeugung ist jetzt vollständig überprüfbar: `NoteStore` erzeugt dedizierte `NotificationRequest`s, hält den Scheduler stark und meldet fehlende Scheduler explizit statt lautlos nichts zu tun; der iOS-Adapter wartet auf das asynchrone `UNUserNotificationCenter.add`.
- Die Archivordner-Auswahl ist in der App produktiv über `UIDocumentPickerViewController` verdrahtet und speichert ein Bookmark, das beim Monatsarchiv-Export wieder aufgelöst und als Security-Scoped Resource geöffnet wird.
- iCloud-Synchronisation ist in der App über `NSUbiquitousKeyValueStore` angebunden: lokale Snapshots werden nach Änderungen veröffentlicht, entfernte Snapshots werden beim Start und bei iCloud-Änderungen verlustfrei über den vorhandenen `SyncEngine` gemerged.
- Die Einstellungen zeigen nun die echte Ordnerauswahl, behalten den manuellen Pfad als Fallback und beschreiben die automatische iCloud-Übertragung statt nur eine vorbereitete Schnittstelle.

## Fortschritt: Performance-Pass
- Der Appstart rendert jetzt zuerst den lokalen Snapshot; iCloud-Start, iCloud-Erstmerge und Monatsarchiv-Prüfung laufen anschließend als Hintergrund-Arbeit auf dem MainActor an, damit die erste Seite schneller interaktiv wird.
- Texteingaben schreiben den Store weiterhin sofort für flüssige UI, bündeln aber JSON-Persistenz und iCloud-Veröffentlichung mit einem kurzen Debounce statt bei jedem Tastendruck synchron Datei- und iCloud-I/O auszulösen.
- Beim Wechsel in den Hintergrund werden ausstehende Schreibvorgänge explizit geflusht, sodass die Debounce-Optimierung keine Daten verliert.
- Editor-State wird nur noch aktualisiert, wenn Remote-/Delete-Änderungen tatsächlich andere Werte liefern; dadurch wird die laufende Tastatureingabe weniger durch selbst ausgelöste Store-Updates gestört.

## Fortschritt: Performance-Pass 2
- Lokale Snapshots werden bei jeder Änderung wieder sofort atomar geschrieben, damit selbst ein plötzlicher App-Abbruch möglichst keine Texteingabe verliert; nur die teurere iCloud-Veröffentlichung bleibt debounced.
- Das Löschen einer Seite ist gegen nachlaufende SwiftUI-`onChange`-Callbacks abgesichert: programmatische Editor-Synchronisierung unterdrückt Speichervorgänge, damit ein geleerter Slot nicht unbeabsichtigt direkt wieder angelegt wird.
- Für flüssigere Wischanimationen gibt es nur noch einen gemeinsamen `NavigationStack` um die Kartenansicht statt eines NavigationStacks pro Seite; der Kartenwechsel nutzt eine kurze interaktive Spring-Animation.
