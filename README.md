# FLOW 8 Web Remote

🇬🇧 **English version: [see below](#english).**

![FLOW 8 Web Remote – Screenshot der Oberfläche / screenshot of the interface](images/screenshot.png)

Inoffizielle Fernsteuerung für das **Behringer FLOW 8** im Browser: eine einzige HTML-Seite, ohne Installation, ohne Cloud, ohne Konto.

> **Du brauchst nur einen Chromium-Browser**, z. B. **Microsoft Edge** oder **Google Chrome**. Nichts installieren. Firefox und Safari gehen nicht (ihnen fehlen Web MIDI und Web Bluetooth).

> **100 % vibe coded mit Claude.** Privates Hobbyprojekt, komplett im Dialog mit Claude (Anthropic) entstanden und geteilt, falls es jemand nützlich findet. Kein Support, keine Garantie, Rückmeldungen willkommen. Nicht von Behringer / Music Tribe; „Behringer“ und „FLOW 8“ sind Marken ihrer Inhaber.

## So startest du

Du brauchst: das FLOW 8, ein USB-Kabel und einen PC mit Edge oder Chrome.

1. **Herunterladen:** Oben auf dieser Seite auf den grünen Knopf **Code** klicken, dann **Download ZIP**.
2. **Entpacken:** ZIP-Datei mit Rechtsklick → **Alle extrahieren** in einen eigenen Ordner auspacken.
3. **Anschließen:** FLOW 8 einschalten und per USB mit dem PC verbinden.
4. **Starten:**
   - **Windows:** `start-mixer.bat` doppelklicken. Edge öffnet sich mit der Seite. Warnt Windows, auf **Weitere Informationen** → **Trotzdem ausführen** klicken (die Datei ist lesbarer Klartext).
   - **Mac / Linux:** `flow8-mixer-ble.html` mit Chrome oder Edge öffnen (Rechtsklick → Öffnen mit). Hier fehlen nur die Audio-Anzeigen (Pegel und RTA).
5. **Erlauben:** Fragt der Browser nach MIDI-Zugriff, auf **Zulassen** klicken. Dann einmal irgendwo auf die Seite klicken, im Bluetooth-Fenster das **FLOW 8** wählen und **Koppeln**.
6. **Fertig:** Sobald der Mixerzustand angekommen ist, werden die Regler freigeschaltet.

Tipp: Das FLOW 8 nimmt per Bluetooth nur **ein** Gerät an. Vorher in der Handy-App Bluetooth trennen.

## Was es kann

- Kanalzüge, Busse und Main: Fader, Mute, Solo, Pan, Gain, Kompressor, Low Cut, Phase, EQ, Sends, Delay, Limiter
- Effekte (FX 1 / FX 2) und Snapshots 1–15
- Steuerung per **MIDI (USB)** und **Bluetooth**; Farben zeigen, welcher Weg für welches Element gilt
- Pegelanzeigen und **Echtzeit-Analyzer (RTA)** über die USB-Audioverbindung (Windows)
- Mehrere Sprachen, eigene Farben

**Sicherheitsregeln:** Es wird nichts automatisch verstellt, die Seite sendet nur, was du bedienst. 48V nur von Hand mit Rückfrage. Reset, Werksreset und Snapshot speichern/löschen gibt es bewusst nicht.

## Sprachen

Auswahl unter **Global → Mixer-Einstellungen → Sprache**. Standard ist Englisch, Deutsch ist dabei.

**Eigene Sprache erstellen:**

1. `languages/en.txt` kopieren und umbenennen, z. B. `fr.txt`.
2. Erste Zeile anpassen: `language:Français` (so erscheint sie in der Auswahl).
3. In jeder Zeile nur den Text **rechts** vom ersten Doppelpunkt übersetzen. Links nichts ändern, Platzhalter wie `{n}` stehen lassen.
4. Datei in den Ordner `languages/` legen und die Seite neu laden. Mit `start-mixer.bat` erscheint sie automatisch. Ohne .bat (z. B. Mac): **Sprache → Sprachdatei laden…**
5. Fehlende Zeilen werden auf Englisch angezeigt, du kannst also auch Stück für Stück übersetzen.

Teilen: Datei gern als Pull Request oder Issue einreichen.

## Bewusst simpel und im Klartext

- **Eine HTML-Datei**, kein Build-Schritt, keine Pakete, keine Abhängigkeiten. Alles (auch die `.bat` und die Sprachdateien) ist lesbarer Klartext.
- **Alles lokal:** Die Seite lädt nichts aus dem Internet und sendet nichts nach außen. Der Mini-Server der `.bat` ist nur auf deinem PC erreichbar (`localhost:8000`) und beendet sich selbst.
- **Sprachdateien sind reiner Text**, sie werden nie als Code ausgeführt.
- Einstellungen liegen nur im Speicher deines Browsers.

## Mehr Infos

- **Handbuch (Englisch):** [`docs/MANUAL.md`](docs/MANUAL.md) – Bedienung, Hintergründe, Protokoll
- Bedienungsanleitung als PDF: [Deutsch](FLOW8-Mixer-Bedienungsanleitung.pdf) · [English](FLOW8-Web-Remote-User-Manual.pdf)
- Für Entwickler: Protokoll-Tabelle [`docs/flow8-midi-sysex-ble-tabelle.csv`](docs/flow8-midi-sysex-ble-tabelle.csv), Fader- und Low-Cut-Tabellen in [`docs/`](docs/)

## Herkunft, Haftung, Lizenz

- Das Bluetooth-Protokoll und Teile der MIDI-Zuordnung beruhen auf [abelroes/flow-8-midi](https://github.com/abelroes/flow-8-midi) (nur Protokollfakten, kein Quelltext). Danke!
- Nutzung **auf eigene Gefahr**, ohne Gewähr. Falsche Pegel können Lautsprecher und Gehör gefährden, Phantomspeisung empfindliche Mikrofone.
- Lizenz: [GPL-3.0](LICENSE). Nutzen, ändern und weitergeben erlaubt; weitergegebene Änderungen ebenfalls unter GPL mit Quelltext.

---

<a name="english"></a>
# English

Unofficial browser remote control for the **Behringer FLOW 8**: a single HTML page, no installation, no cloud, no account.

> **All you need is a Chromium-based browser**, e.g. **Microsoft Edge** or **Google Chrome**. Nothing to install. Firefox and Safari do not work (they lack Web MIDI and Web Bluetooth).

> **100% vibe coded with Claude.** A private hobby project, built entirely in conversation with Claude (Anthropic) and shared in case someone finds it useful. No support, no warranty, feedback welcome. Not affiliated with Behringer / Music Tribe; "Behringer" and "FLOW 8" are trademarks of their respective owners.

## Getting started

You need: the FLOW 8, a USB cable and a computer with Edge or Chrome.

1. **Download:** click the green **Code** button at the top of this page, then **Download ZIP**.
2. **Unzip:** right-click the ZIP file → **Extract All** into a folder of its own.
3. **Connect:** switch on the FLOW 8 and connect it to the computer via USB.
4. **Start:**
   - **Windows:** double-click `start-mixer.bat`. Edge opens with the page. If Windows shows a warning, click **More info** → **Run anyway** (the file is readable plain text).
   - **Mac / Linux:** open `flow8-mixer-ble.html` with Chrome or Edge (right-click → Open With). Only the audio displays (meters and RTA) are missing here.
5. **Allow:** when the browser asks for MIDI access, click **Allow**. Then click anywhere on the page once, pick the **FLOW 8** in the Bluetooth window and click **Pair**.
6. **Done:** as soon as the mixer state has arrived, the controls are unlocked.

Tip: the FLOW 8 accepts only **one** Bluetooth device. Disconnect Bluetooth in the phone app first.

## Features

- Channel strips, buses and main: faders, mute, solo, pan, gain, compressor, low cut, phase, EQ, sends, delay, limiter
- Effects (FX 1 / FX 2) and snapshots 1–15
- Control via **MIDI (USB)** and **Bluetooth**; colors show which route each control uses
- Level meters and **real-time analyzer (RTA)** over the USB audio connection (Windows)
- Several languages, custom colors

**Safety rules:** nothing is changed automatically; the page only sends what you operate. 48V only by hand, with confirmation. Reset, factory reset and saving/deleting snapshots are deliberately left out.

## Languages

Select under **Global → Mixer Settings → Language**. English is the default, German is included.

**Create your own language:**

1. Copy `languages/en.txt` and rename it, e.g. `fr.txt`.
2. Change the first line: `language:Français` (this is how it appears in the list).
3. In each line, translate only the text **to the right** of the first colon. Do not change anything on the left; keep placeholders such as `{n}`.
4. Put the file into the `languages/` folder and reload the page. With `start-mixer.bat` it appears automatically. Without the .bat (e.g. on a Mac): **Language → Load Language File…**
5. Missing lines are shown in English, so you can translate bit by bit.

Sharing: feel free to submit your file as a pull request or issue.

## Deliberately simple and plain text

- **One HTML file**, no build step, no packages, no dependencies. Everything (including the `.bat` and the language files) is readable plain text.
- **Everything local:** the page loads nothing from the internet and sends nothing outside. The mini server of the `.bat` is reachable only on your own computer (`localhost:8000`) and shuts itself down.
- **Language files are plain text**; they are never executed as code.
- Settings are stored only in your browser.

## More information

- **Manual:** [`docs/MANUAL.md`](docs/MANUAL.md) – operation, background, protocol
- PDF user manual: [English](FLOW8-Web-Remote-User-Manual.pdf) · [Deutsch](FLOW8-Mixer-Bedienungsanleitung.pdf)
- For developers: protocol table [`docs/flow8-midi-sysex-ble-tabelle.csv`](docs/flow8-midi-sysex-ble-tabelle.csv), fader and low-cut tables in [`docs/`](docs/) (column headers in German)

## Origin, disclaimer, license

- The Bluetooth protocol and parts of the MIDI mapping are based on [abelroes/flow-8-midi](https://github.com/abelroes/flow-8-midi) (protocol facts only, no source code). Thank you!
- Use **at your own risk**, without warranty. Wrong levels can endanger speakers and hearing; phantom power can damage sensitive microphones.
- License: [GPL-3.0](LICENSE). You may use, modify and redistribute it; distributed modifications must also be GPL with source code.
