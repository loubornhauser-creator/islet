# Islet

Eine schlanke Dynamic Island für den Mac, in nativem Swift/SwiftUI, ohne Fremdbibliotheken. Ziel: alles Nützliche von Atoll, aber mit deutlich weniger RAM und CPU, voll anpassbar und mit Liquid Glass.

## Funktionen

- **Spotify**: Cover, Titel, Play/Pause/Skip, Fortschritt zum Spulen, Systemlautstärke (per AppleScript und Benachrichtigungen, kein API-Key)
- **Koffein-Button**: grün, wenn irgendein `caffeinate` läuft (auch aus dem Terminal gestartet), sonst grau. Klick schaltet um, Rechtsklick wählt die Dauer
- **Lautstärke/Helligkeit als Seiten-Bar** wie auf iPhone/iPad, ersetzt das System-HUD
- **Trackpad-Gesten**: am linken/rechten Rand hoch und runter wischen (Standard: Lautstärke links, Helligkeit rechts)
- **Timer und Pomodoro**, Live-Anzeige in der kompakten Insel
- **Akku**, mit Lade-Hinweis beim Anstecken
- **Mini-Stats** für CPU, GPU und RAM, nur aktiv, solange das Panel offen ist
- **Eigene Aktionen**: Kacheln für Shell-Befehl, App oder Link
- Jedes Modul einzeln abschaltbar, Farben, Größe, Rundung, Glas-Tönung frei einstellbar

## Bauen

```bash
./build.sh run      # baut, installiert nach ~/Applications und startet
```

Voraussetzung: macOS 14 oder neuer, Xcode/Swift 5.9 oder neuer. Liquid Glass gibt es ab macOS 26, davor fällt die Oberfläche auf Material zurück.

## Berechtigungen

- **Automation** (Spotify): wird beim ersten Zugriff abgefragt.
- **Bedienungshilfen**: nötig, um Medientasten abzufangen und das Scrollen während einer Rand-Geste zu unterdrücken. Ohne sie läuft der Rest trotzdem.

## Hinweise

- Helligkeit und Trackpad-Gesten nutzen private Apple-Schnittstellen (DisplayServices, MultitouchSupport), die zur Laufzeit geladen werden. Fehlen sie, ist die Funktion einfach nicht verfügbar. Daher kein App-Store-Release.
- Atoll selbst steht unter GPL. Islet ist eine unabhängige Neuentwicklung ohne Atoll-Code.

Lizenz: MIT
