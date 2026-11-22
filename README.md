# Islet

Eine schlanke Dynamic Island für den Mac, in nativem Swift/SwiftUI, ohne Fremdbibliotheken. Ziel: alles Nützliche von Atoll, aber mit deutlich weniger RAM und CPU, voll anpassbar.

## Funktionen

**Insel** (schwarz, mit der Notch verschmolzen, klappt beim Überfahren oder per Tastenkürzel auf)

- **Musik** (Spotify): Cover, Titel, Play/Pause/Skip, Fortschritt zum Spulen. Per AppleScript und Benachrichtigungen, kein API-Key
- **Übersicht**: Koffein, Timer, Akku, Stats (CPU/GPU/RAM) und Schnell-Schalter (Dunkel/Hell, Stumm, Display aus)
- **Zwischenablage**: Verlauf der letzten Texte, nur im Arbeitsspeicher, Passwort-Manager werden ignoriert
- **Aktionen**: eigene Kacheln für Shell-Befehl, App oder Link, mit Vorlagen

**Kompakte Insel** zeigt live neben der Notch: Cover bei Musik, Koffein-Symbol, Timer-Restzeit, Lade-Hinweis, Mikrofon- und Kamera-Punkt

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
- **Bedienungshilfen**: nötig, um Medientasten abzufangen und das Scrollen während einer Rand-Geste zu unterdrücken. Ohne sie läuft der Rest trotzdem.

Der aktuelle Status steht in den Einstellungen unter „Berechtigungen“.

## Hinweise

- Helligkeit und Trackpad-Gesten nutzen private Apple-Schnittstellen (DisplayServices, MultitouchSupport), die zur Laufzeit geladen werden. Fehlen sie, ist die Funktion einfach nicht verfügbar. Daher kein App-Store-Release.
- Atoll selbst steht unter GPL. Islet ist eine unabhängige Neuentwicklung ohne Atoll-Code.

Lizenz: MIT
