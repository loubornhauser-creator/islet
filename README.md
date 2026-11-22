# Islet

Eine schlanke Dynamic Island für den Mac, in nativem Swift/SwiftUI, ohne Fremdbibliotheken. Ziel: alles Nützliche von Atoll, aber mit deutlich weniger RAM und CPU, voll anpassbar.

## Funktionen

**Insel** (schwarz, mit der Notch verschmolzen, klappt beim Überfahren oder per Tastenkürzel auf)

- **Musik** (Spotify): Cover, Titel, Play/Pause/Skip, Fortschritt zum Spulen. Per AppleScript und Benachrichtigungen, kein API-Key
- **Übersicht**: Koffein, Timer, Akku, Stats (CPU/GPU/RAM) und Schnell-Schalter (Dunkel/Hell, Stumm, Display aus)
- **Kalender**: nächste Termine (EventKit, nur lesend) und offene Apple-Erinnerungen (überfällige oben, Abhaken per Klick), Auswahl der Kalender und Listen, Countdown kurz vor Beginn in der kompakten Insel
- **Geräte**: verbundene Bluetooth-Geräte mit Akkustand (AirPods links/rechts/Hülle, Maus, Tastatur). Beim Verbinden von AirPods erscheinen Symbol und Akkustand neben der Notch
- **Claude-Limits**: Session- (5 Std) und Wochen-Limit live, über die Anmeldung von Claude Code im Schlüsselbund (opt-in, macOS fragt einmal um Erlaubnis)
- **Zwischenablage**: Verlauf der letzten Texte, nur im Arbeitsspeicher, Passwort-Manager werden ignoriert
- **Aktionen**: eigene Kacheln für Shell-Befehl, App oder Link, mit Vorlagen

**Kompakte Insel** zeigt live neben der Notch: Cover bei Musik, Koffein-Symbol, Timer-Restzeit, Lade-Hinweis, Termin-Countdown, neu verbundene AirPods, Mikrofon- und Kamera-Punkt

**Face Unlock** (Komfort-Funktion, kein Ersatz für Face ID): Einrichtung mit Passwort-Prüfung und Einlernen aus 9 Kopfwinkeln, Gesichtserkennung nur mit Apples Vision-Framework (kein Modell, kein Download), Scan beim Aufwachen, Animation in der Notch, Passwort wird nur bei wirklich gesperrtem Bildschirm und höchstens zweimal getippt. Zuerst als Probelauf ohne Tippen. Gesicht und Passwort liegen verschlüsselt (AES-GCM, an Mac und Benutzer gebunden) in einer Datei, ohne Schlüsselbund-Abfragen

**Tastatur reinigen**: sperrt Tastatur und Trackpad, Esc 3 Sekunden halten beendet sofort

**Koffein-Button**: grün, wenn irgendein `caffeinate` läuft (auch aus dem Terminal gestartet), sonst grau. Klick schaltet um, Rechtsklick wählt die Dauer, Restzeit wird angezeigt

**Timer**: Pause/Fortsetzen, +5 Min, Pomodoro, Ton am Ende

**Seiten-Bar** für Lautstärke und Helligkeit wie auf iPhone/iPad, ersetzt das System-HUD (Symbol je nach Ausgabegerät)

**Trackpad-Gesten**: am Rand hoch und runter wischen (Standard: Lautstärke links, Helligkeit rechts)

**Einstellungen**: Seitenleiste, Live-Vorschau, Farbvorlagen, eigene Farben, Größe und Rundung, Bildschirmwahl, globales Tastenkürzel, Start bei Login, Vollbild-Erkennung, Export/Import, Berechtigungs-Status. Jedes Modul ist einzeln abschaltbar und läuft dann gar nicht.

## Bauen

```bash
./build.sh run      # baut, installiert nach ~/Applications und startet
```

Voraussetzung: macOS 14 oder neuer, Xcode/Swift 5.9 oder neuer. Liquid Glass (optionaler Stil) gibt es ab macOS 26, davor fällt er auf Material zurück.

## Testen ohne Bedienung

```bash
Islet --selftest                                   # Koffein-Erkennung, Helligkeit, Audio, Gesten
Islet --snapshot out.png --tab overview            # Insel in eine PNG rendern
Islet --snapshot-settings out.png --page general   # Einstellungsseite rendern
```

## Berechtigungen

- **Automation** (Spotify, System Events): wird beim ersten Zugriff abgefragt.
- **Kalender**: wird beim ersten Start abgefragt, Islet liest nur.
- **Bluetooth**: keine Berechtigung nötig, der Akkustand kommt über die Systeminformationen.
- **Bedienungshilfen**: nötig, um Medientasten abzufangen und das Scrollen während einer Rand-Geste zu unterdrücken. Ohne sie läuft der Rest trotzdem.

Der aktuelle Status steht in den Einstellungen unter „Berechtigungen“.

## Hinweise

- Helligkeit und Trackpad-Gesten nutzen private Apple-Schnittstellen (DisplayServices, MultitouchSupport), die zur Laufzeit geladen werden. Fehlen sie, ist die Funktion einfach nicht verfügbar. Daher kein App-Store-Release.
- Atoll selbst steht unter GPL. Islet ist eine unabhängige Neuentwicklung ohne Atoll-Code.

Lizenz: MIT
