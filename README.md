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
- Pegelanzeigen und **Echtzeit-Analyzer (RTA)** über die USB-Audioverbindung (Windows). Gemessen dort, wo das FLOW 8 seine USB-Aufnahmespuren abgreift: Eingangskanäle direkt nach dem Gain ohne Low Cut und EQ, Main ohne Main-EQ
- Mehrere Sprachen, eigene Farben
- **Fernsteuerung mit X-Air-Apps** (Windows): Handy, Tablet oder ein zweiter PC im selben WLAN (siehe unten)

**Sicherheitsregeln:** Es wird nichts automatisch verstellt, die Seite sendet nur, was du bedienst. 48V nur von Hand mit Rückfrage. Reset, Werksreset und Snapshot speichern/löschen gibt es bewusst nicht.

## Sprachen

Auswahl unter **Global → Mixer Settings → Language** (auf Deutsch: Mixer-Einstellungen → Sprache). Standard ist Englisch, Deutsch ist dabei.

**Eigene Sprache erstellen:**

1. `languages/en.txt` kopieren und umbenennen, z. B. `fr.txt`.
2. Erste Zeile anpassen: `language:Français` (so erscheint sie in der Auswahl).
3. In jeder Zeile nur den Text **rechts** vom ersten Doppelpunkt übersetzen. Links nichts ändern, Platzhalter wie `{n}` stehen lassen.
4. Datei in den Ordner `languages/` legen und die Seite neu laden. Mit `start-mixer.bat` erscheint sie automatisch. Ohne .bat (z. B. Mac): **Language → Load Language File…** (Sprache → Sprachdatei laden…)
5. Fehlende Zeilen werden auf Englisch angezeigt, du kannst also auch Stück für Stück übersetzen.

Teilen: Datei gern als Pull Request oder Issue einreichen.

## Fernsteuerung mit X-Air-Apps

Während die Seite über `start-mixer.bat` läuft, meldet sich der PC im Netzwerk wie ein **Behringer XR12** (X-Air-Protokoll, UDP-Port 10024). Jede X-Air-kompatible App im selben WLAN kann das FLOW 8 dann darüber steuern; welche App, entscheidest du.

1. PC und Handy/Tablet ins selbe WLAN.
2. `start-mixer.bat` starten. Fragt die Windows-Firewall, den Zugriff für **private Netzwerke** erlauben.
3. In der App ein X-Air-Pult **XR12** suchen bzw. die IP-Adresse des PCs eingeben.

Was das FLOW 8 nicht kann (z. B. weitere Kanäle oder Effekte des XR12), hat keine Wirkung. **48V und Snapshots** gehen bewusst nur am PC. Das X-Air-Protokoll hat keinen Code und kein Login: Solange die Seite läuft, kann jedes Gerät im selben WLAN steuern. Status und Protokoll stehen unter **Global → X-Air Remote**. Die Zuordnung ist noch neu; was nicht passt, wird Schritt für Schritt verbessert.

## Bewusst simpel und im Klartext

- **Eine HTML-Datei**, kein Build-Schritt, keine Pakete, keine Abhängigkeiten. Alles (auch `start-mixer.bat`, der Server `flow8-server.ps1` und die Sprachdateien) ist lesbarer Klartext.
- **Kein Internet:** Die Seite lädt nichts aus dem Internet und sendet nichts nach außen. Die Webseite des Mini-Servers ist nur auf deinem PC erreichbar (`localhost:8000`). Einzige Ausnahme ist der X-Air-Port 10024 im eigenen WLAN (siehe oben). Der Server beendet sich selbst, wenn die Seite geschlossen wird.
- **Sprachdateien sind reiner Text**, sie werden nie als Code ausgeführt.
- Einstellungen liegen nur im Speicher deines Browsers.

## Mehr Infos

- **Technisches Handbuch (Englisch):** [`docs/MANUAL.md`](docs/MANUAL.md) – MIDI, SysEx-Dump, Bluetooth, X-Air-Emulation, Kurven und Umrechnungen, Audio/RTA, Sprachdateien
- Bedienungsanleitung für Einsteiger (PDF, Englisch): [`FLOW8-Web-Remote-User-Manual.pdf`](FLOW8-Web-Remote-User-Manual.pdf)
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
- Level meters and **real-time analyzer (RTA)** over the USB audio connection (Windows). Measured where the FLOW 8 taps its USB recording tracks: input channels right after the gain without low cut and EQ, main without the main EQ
- Several languages, custom colors
- **Remote control with X-Air apps** (Windows): phone, tablet or a second computer in the same network (see below)

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

## Remote control with X-Air apps

While the page runs via `start-mixer.bat`, the computer appears on the network like a **Behringer XR12** (X-Air protocol, UDP port 10024). Any X-Air compatible app in the same network can then control the FLOW 8 through it; which app is up to you.

1. Put the computer and the phone/tablet in the same network.
2. Start `start-mixer.bat`. If the Windows firewall asks, allow access for **private networks**.
3. In the app, search for an X-Air mixer **XR12** or enter the computer's IP address.

Anything the FLOW 8 cannot do (e.g. the XR12's extra channels or effects) has no effect. **48V and snapshots** deliberately work only on the computer. The X-Air protocol has no code and no login: while the page is running, every device in the same network can control the mixer. Status and log are under **Global → X-Air Remote**. The mapping is new; whatever does not fit yet will be improved step by step.

## Deliberately simple and plain text

- **One HTML file**, no build step, no packages, no dependencies. Everything (including `start-mixer.bat`, the server `flow8-server.ps1` and the language files) is readable plain text.
- **No internet:** the page loads nothing from the internet and sends nothing outside. The mini server's web page is reachable only on your own computer (`localhost:8000`). The only exception is the X-Air port 10024 in your own network (see above). The server shuts itself down when the page is closed.
- **Language files are plain text**; they are never executed as code.
- Settings are stored only in your browser.

## More information

- **Technical manual:** [`docs/MANUAL.md`](docs/MANUAL.md) – MIDI, SysEx dump, Bluetooth, X-Air emulation, curves and conversions, audio/RTA, language files
- Beginner's user manual (PDF): [`FLOW8-Web-Remote-User-Manual.pdf`](FLOW8-Web-Remote-User-Manual.pdf)
- For developers: protocol table [`docs/flow8-midi-sysex-ble-tabelle.csv`](docs/flow8-midi-sysex-ble-tabelle.csv), fader and low-cut tables in [`docs/`](docs/) (protocol and fader tables have German column headers)

## Origin, disclaimer, license

- The Bluetooth protocol and parts of the MIDI mapping are based on [abelroes/flow-8-midi](https://github.com/abelroes/flow-8-midi) (protocol facts only, no source code). Thank you!
- Use **at your own risk**, without warranty. Wrong levels can endanger speakers and hearing; phantom power can damage sensitive microphones.
- License: [GPL-3.0](LICENSE). You may use, modify and redistribute it; distributed modifications must also be GPL with source code.
