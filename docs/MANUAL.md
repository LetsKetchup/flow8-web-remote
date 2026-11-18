# FLOW 8 Web Remote – Technical Manual

Reference for developers, power users and anyone curious about how the page talks to the **Behringer FLOW 8**. For step-by-step operation see the [user manual (PDF)](../FLOW8-Web-Remote-User-Manual.pdf).

Everything here was reverse-engineered or taken from public sources. Nothing is official. Each fact carries a status:

| Status | Meaning |
|---|---|
| **confirmed** | verified on real hardware during development |
| **per docs** | from Behringer's MIDI documentation, not yet tested |
| **library** | encoding taken from the community project [abelroes/flow-8-midi](https://github.com/abelroes/flow-8-midi) (protocol facts only, no code) |
| **pattern** | assumed from the layout of neighbouring channels |
| **open** | unknown |

Machine-readable tables live next to this file:

| File | Content |
|---|---|
| [`FLOW8-MIDI-Implementation.md`](FLOW8-MIDI-Implementation.md) | the MIDI implementation as a standalone chart with FAQ (same facts as §3 and §6; also published as the GitHub Pages start page `website/index.html`) |
| [`flow8-midi-sysex-ble-tabelle.csv`](flow8-midi-sysex-ble-tabelle.csv) | all MIDI messages, SysEx offsets and BLE packets with conversions and status (German headers) |
| [`flow8-fader-tabelle.csv`](flow8-fader-tabelle.csv) | BLE fader index 0–255 → dB |
| [`flow8-lowcut-mapping.csv`](flow8-lowcut-mapping.csv) | low cut, measured on channel 1: MIDI CC 9 sent → value in the dump (Hz) → BLE 0x04 value that sets the same frequency |

---

## Contents

1. [Architecture](#1-architecture)
2. [Data flow](#2-data-flow)
3. [MIDI implementation](#3-midi-implementation)
4. [SysEx state dump](#4-sysex-state-dump)
5. [Bluetooth LE protocol](#5-bluetooth-le-protocol)
6. [Conversions and curves](#6-conversions-and-curves)
7. [Audio: meters and RTA](#7-audio-meters-and-rta)
8. [EQ display and detail tabs](#8-eq-display-and-detail-tabs)
9. [Language files](#9-language-files)
10. [Tablet interface](#10-tablet-interface)
11. [Files and tools](#11-files-and-tools)
12. [Limits and open questions](#12-limits-and-open-questions)

---

## 1 Architecture

- **One file:** `flow8-mixer-ble.html` contains HTML, CSS and JavaScript. There is no build step and there are no dependencies or external requests.
- **Browser APIs:**
  - **Web MIDI** with SysEx permission, for USB MIDI.
  - **Web Bluetooth**, for BLE GATT.
  - **getUserMedia + Web Audio**, for USB audio.
  - These need a Chromium-based browser (Edge, Chrome).
- **Local mini server:** optional. `start-mixer.bat` starts `flow8-server.ps1`: a small HTTP server in PowerShell (`TcpListener` on port **8000**, all interfaces, no admin rights needed). It runs single-threaded: one loop accepts connections, reads requests and answers them; between rounds it waits in `Socket.Select` (at most 20 ms) instead of sleeping, so a request is handled as soon as it arrives. Connections the browser has closed are dropped at once. One failing request is logged in the server window (`Error: … (line …)`) and does not stop the server. Requests from this computer (loopback) are always allowed. Requests from other devices need the access code if the page requires one (§10), and the routes marked *PC only* refuse them with 403.

  | Route | Purpose |
  |---|---|
  | `/<file>` | static files from the folder (`..` blocked); `.html` as UTF-8, `.txt` as `text/plain; charset=utf-8` |
  | `/languages` | plain-text list of all file names in `languages/`, one per line |
  | `/ping` | *PC only.* Heartbeat from the page every 5 s; the server stops 90 s after the last ping |
  | `/bye` | *PC only.* Sent on page close (`sendBeacon`); the server stops 8 s later |
  | `/audio` | *PC only.* `POST` from the Firefox feeder (levels and spectra as JSON), `GET` from the page every 60 ms |
  | `/r/sec` | *PC only.* `POST "<on 1\|0> <req 1\|0> <code>"`: remote control on/off, access code required yes/no, the code |
  | `/r/info` | *PC only.* `GET`: line 1 = number of devices seen in the last 15 s, line 2 = the computer's IPv4 addresses (read from the network adapters, no DNS lookup, cached 30 s; 169.254.x.x left out) |
  | `/r/state` | `POST` (*PC only*): latest state as JSON. `GET ?v=N` (devices): answers at once if the stored version differs from `N`, else waits up to 10 s (204). Header `X-Ver` = version |
  | `/r/cmd` | `POST` (devices): commands, one JSON object per line. `GET` (*PC only*): waits up to 1 s and returns the queued lines |
  | `/r/audio` | `POST` (*PC only*): levels and spectra for devices. `GET ?ev=1` (devices): event stream (`text/event-stream`), every posted frame is pushed at once as `data: …`, a comment line every 10 s keeps it alive. Plain `GET`: latest frame, 204 if none (fallback for browsers without `EventSource`) |

  Why a server at all: `getUserMedia` device labels, the Firefox feeder and the language folder need a real origin. Opened as `file://`, the page still works but without audio and with only the built-in English text.
- **Online (GitHub Pages):** the workflow `.github/workflows/pages.yml` publishes `website/` (start page `index.html` = the MIDI chart, `sitemap.xml`) together with `flow8-mixer-ble.html`, `images/` and `languages/` at `https://letsketchup.github.io/flow8-web-remote/` (Pages source: *GitHub Actions*). `.gitattributes` keeps `website/` and `.github/` out of GitHub's *Download ZIP*. `website/index.html` is generated from `docs/FLOW8-MIDI-Implementation.md`; regenerate it after changing the chart. Served over `https:`, so `REMOTE` and `LANPC` are both false (they test for `http:`) and the page behaves like the `file://` case: MIDI, BLE, dumps and all controls work. No tablet relay, no `/languages` list (built-in English plus *Load Language File…*), no Firefox feeder. Audio via `getUserMedia` should work on an `https:` origin but is untested. `localStorage` belongs to the `github.io` origin, separate from `localhost:8000`.
- **Browser storage:** everything is kept in `localStorage`, nothing else is stored.

  | Key | Content |
  |---|---|
  | `flow8.mode` | `midi` / `ble` – route for “both” controls |
  | `flow8.out` | name of the last MIDI output |
  | `flow8.colors` | color settings (JSON) |
  | `flow8.audio` | audio/RTA settings and track mapping (JSON); on tablets the RTA part always follows the PC |
  | `flow8.lang` | selected language file |
  | `flow8.langfile` | language file loaded via file picker (name + text); listed as “Name (loaded file)”, code `file:<name>`, removable with the *Remove* button next to the menu |
  | `flow8.sec` | Remote window: `{"on": true/false, "req": true/false, "code": "…"}` |
  | `flow8.view` | on tablets/phones: `tablet` (default) or `full` |

- **Safety rules (by design):**
  - Nothing is sent without a user action.
  - 48V needs a confirmation dialog.
  - Snapshot 16 (reset), factory reset, snapshot save/delete and SysEx writes are not implemented.
  - The checkbox *Sending enabled* blocks all output, also from phones and tablets.
  - From phones and tablets, snapshot commands are refused (48V is allowed, with the confirmation on the device), and the PC page accepts only the message types listed in §10.

## 2 Data flow

```
                 BLE write 4B 01 4C (dump request)
   Page ───────────────────────────────────────────► FLOW 8
    ▲                                                   │
    │   SysEx dump (3068 bytes) over USB MIDI           │
    └───────────────────────────────────────────────────┘
   Controls → MIDI CC / Program Change (USB) or BLE packet (GATT write)
```

- **Getting the state:** the mixer has no MIDI request for its state. The page asks over BLE (`4B 01 4C`), and the mixer answers with a SysEx dump on **USB MIDI**. Without MIDI there is therefore no state. Alternatively, trigger *MIDI dump → Yes* in the FLOW app or load a `.syx` file.
- **Auto update:** the request is repeated every 0.5 / 1 / 2 s.
  - A dump whose body (from byte 24 on) equals the previous one is ignored.
  - A dump that arrives while the user is operating a control is discarded: from pointer down until release (at most 30 s), and for 700 ms after any input. The next dump follows anyway.
- **Sending:** every control has a route.
  - **MIDI only** (red), **BLE only** (blue) or **both** (purple). For “both”, the header switch decides.
  - Repeated values of the same control are coalesced every 25 ms (the last value wins), separately for MIDI and BLE.
  - BLE writes are serialized (`writeValueWithResponse`), because GATT allows only one operation at a time.
- **Unknown-byte alarm:** after each new dump, every byte that belongs to no known field and jumps from `00` to another value triggers a full-screen warning. The warning lists the offset, the nearest known field before it and the last action of the page.

## 3 MIDI implementation

**Channels** (status: tested)

| MIDI channel | Target |
|---|---|
| 1–7 | inputs: Ch 1, 2, 3, 4, 5/6, 7/8, USB/BT (channel = ID + 1) |
| 8–12 | buses: MAIN, MON 1, MON 2, FX 1, FX 2 |
| 13 | **unused** (tested: no CC, Program Change, note, pitch bend or pressure changes the state) |
| 14 / 15 | FX slot 1 / 2 (parameters, preset). **The Behringer documentation says 13 / 14; that is wrong** (tested). |
| 16 | global (snapshots, FX mute, tap tempo) |

**How the map was checked.** A test page sent every CC (values 127 and 0), Program Change, note on/off, poly aftertouch, pitch bend and channel pressure on all 16 channels, plus MIDI clock, start/stop, song position and song select, and compared a state dump after each step. Known commands were skipped (48V CC 12 and snapshot Program Changes were never sent). Everything that changed the dump is listed below; nothing else changed the dump. Effects that do not show in the dump (e.g. tap tempo) cannot be found this way.

**Input channels** (MIDI channel 1–7)

| CC | Function | Value | Status |
|---|---|---|---|
| 1–4 | EQ band 1–4 gain | 64 = 0 dB, ±15 dB (§6) | per docs |
| 5 | mute | 127 on / 0 off | per docs |
| 6 | solo | 127 / 0 | per docs |
| 7 | send level → MAIN | level curve (§6) | confirmed |
| 8 | gain | −20…+60 dB (§6) | confirmed |
| 9 | low cut frequency | 128 steps, 20–600 Hz (§6) | confirmed, all 128 values measured |
| 21–24 | EQ band 1–4 frequency | 20 Hz…20 kHz, logarithmic (§6) | confirmed, measured on all inputs |
| 31–34 | EQ band 1–4 Q | 0…19.7, linear (§6); 0 = shelf on bands 1 and 4 | confirmed, measured on all inputs |
| 10 | pan | 1–127, 64 = center | confirmed |
| 11 | compressor | 0–100 (%) | confirmed |
| 12 | 48V phantom | 127 / 0, **channels 1 and 2 only** | per docs |
| 14–17 | send level → MON 1, MON 2, FX 1, FX 2 | level curve | per docs |

**Buses** (MIDI channel 8–12)

| CC | Function | Value | Status |
|---|---|---|---|
| 7 | master fader | level curve | confirmed |
| 8 | limiter (MAIN, MON 1, MON 2) | −30…0 dB (§6) | per docs |
| 10 | balance (MAIN, MON 1, MON 2, FX 1, FX 2) | like pan | MAIN per docs; FX buses confirmed (audible); MON 1/2 confirmed in the dump |
| 11–19 | 9-band EQ gain (MAIN, MON 1, MON 2) | 64 = 0 dB, ±15 dB | per docs |
| 21–29 | 9-band EQ frequency (MAIN, MON 1, MON 2) | 20 Hz…20 kHz, logarithmic (§6) | confirmed |
| 31–39 | 9-band EQ Q (MAIN, MON 1, MON 2) | 0…19.7, linear (§6); the FLOW app also goes down to 0 | confirmed |

On the FX buses (channels 11/12), CC 11–19, 21–29 and 31–39 change an EQ block in the dump (b = 2172 / 2272), but the EQ has **no audible effect** (tested). The page does not offer it. CC 8 (limiter) does nothing there; the FX buses have no limiter.

With the monitor stereo link on (dump 2605), MIDI channel 9 and 10 each change the EQ of both monitors.

**FX and global**

| Message | Function | Status |
|---|---|---|
| CC 1 on ch 14/15 | FX parameter 1, 0–100 % | confirmed |
| CC 2 on ch 14/15 | FX parameter 2: 0 = A, 127 = B | confirmed |
| CC 3 on ch 14/15 | FX parameter 3, value = CC, limited to 100 | dump confirmed; meaning unknown, not offered in the FLOW app |
| Program Change on ch 14/15 | FX preset, Program Change *n* = preset *n* (1–16) | confirmed; values above 16 seem to select preset 16 (unverified) |
| CC 1 on ch 16 | FX mute 127 / 0 | per docs |
| Program Change on ch 16 | load snapshot 1–15 (16 = reset, never sent) | per docs |
| Note On ch 16, note 0, velocity 100 | tap tempo; only affects FX 2 presets 1–12 (delay and echo) | confirmed |

**FX preset names** (from the FLOW app; parameter 1 name, then the names of parameter 2 values A / B)

| Preset | FX 1 | FX 2 |
|---|---|---|
| 1 | AMBIENCE: DECAY, INSTRUMENT / VOCAL | DELAY 1/1: FEEDBACK, DULL / BRIGHT |
| 2 | PERC-REV1: DECAY, DULL / BRIGHT | DELAY 1/2: FEEDBACK, DULL / BRIGHT |
| 3 | PERC-REV2: DECAY, DULL / BRIGHT | DELAY 1/3: FEEDBACK, DULL / BRIGHT |
| 4 | GUIT-REV1: DECAY, LESS BASS / MORE BASS | DELAY 2/1: FEEDBACK, DULL / BRIGHT |
| 5 | GUIT-REV2: DECAY, LESS BASS / MORE BASS | ECHO 1/1: FILTER, SOFT / STRONG |
| 6 | CHAMBER: DECAY, PRE-D OFF / PRE-D ON | ECHO 1/2: FILTER, SOFT / STRONG |
| 7 | ROOM: DECAY, INSTRUMENT / VOCAL | ECHO 1/3: FILTER, SOFT / STRONG |
| 8 | CONCERT: DECAY, INSTRUMENT / VOCAL | ECHO 2/1: FILTER, SOFT / STRONG |
| 9 | CHURCH: DECAY, INSTRUMENT / VOCAL | WIDE ECHO: FILTER, WIDE / NARROW |
| 10 | CATHEDRAL: DECAY, SMALL / LARGE | PING PONG: FILTER, WIDE / NARROW |
| 11 | TEMPLE: DECAY, PRE-D OFF / PRE-D ON | PING P 1/3: FILTER, WIDE / NARROW |
| 12 | STADIUM: DECAY, PRE-D OFF / PRE-D ON | PING P R>L: FILTER, WIDE / NARROW |
| 13 | FLANGER: MOD SPEED, MONO / STEREO | FLANGER: MOD SPEED, MONO / STEREO |
| 14 | SOFT CHOR: DENSITY, TREM OFF / TREM ON | SOFT CHOR: DENSITY, TREM OFF / TREM ON |
| 15 | WARM CHOR: DENSITY, TREM OFF / TREM ON | WARM CHOR: DENSITY, TREM OFF / TREM ON |
| 16 | DEEP CHOR: DENSITY, TREM OFF / TREM ON | DEEP CHOR: DENSITY, TREM OFF / TREM ON |

**Not available over MIDI:**
- phase
- low cut on/off
- 48V on channels 3/4
- delay
- FX routing and tempo
- all global settings
- bus mute/solo (tested: CC 5 / CC 6 on the bus channels 8–12 have no effect)

These need BLE.

**SysEx:** the FLOW 8 sends its state dump over MIDI (after a BLE request or *MIDI dump* in the app), but it answers no SysEx request over MIDI. Tested without any reply: the universal identity request (`F0 7E 7F/00/01 06 01 F7`), and `F0 00 20 32 21 xx F7`, `F0 00 20 32 7F 21 xx F7`, `F0 00 20 32 00 21 xx F7` for all xx 0–127. There is therefore no known way to request the state over MIDI alone. Whether the mixer accepts a dump sent back to it is untested.

## 4 SysEx state dump

**Frame**

- 3068 bytes: `F0 00 20 32 21` · packed data · 3 trailing bytes · `F7`. `00 20 32` is the Behringer manufacturer ID. (confirmed)
- **7-bit packing:** from byte 5, groups of 7 bytes = 1 mask byte + 6 data bytes. Bit *k* of the mask is the missing bit 7 of data byte *k*. Unpacked: **2622 bytes**, starting with ASCII `FLOW`. (confirmed)
- Numbers are little-endian: `f32` = float32, `u16`, `u8`. All offsets below refer to the **unpacked** stream.
- Bytes 0–23 are a header with a counter and are ignored when comparing dumps.

**IDs** (confirmed)

| ID | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 9 | 10 | 11 | 12 | 13 | 15 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Channel | Ch 1 | Ch 2 | Ch 3 | Ch 4 | Ch 5/6 | Ch 7/8 | USB/BT | Phones | MON 1 | MON 2 | FX 1 | FX 2 | MAIN |

**Global blocks**

| Offset | Type | Content | Status |
|---|---|---|---|
| 24 + 4·(16·src + dst) | f32 | level matrix in dB, 16 × 16. Diagonal [id][id] (10–15) = bus master fader, [9][9] = headphone level | confirmed |
| 1048 + id | u8 | mute | confirmed |
| 1064 + id | u8 | solo | confirmed |
| 1096 + 4·id | f32 | pan / balance −1…+1 | confirmed (Ch 4), others pattern |
| 1164 + 26·id | 5 × ASCII | channel name, ends at a byte outside 32–126 | confirmed |
| 1164 + 26·id − 2 | u16 | icon number (0 = none) | numbering open |

**Input block** g = 1580 + 56·id (id 0–6)

| Offset | Type | Content | Status |
|---|---|---|---|
| g − 4 | u8 | low cut on (id 0–5; USB/BT has no low cut, tested) | confirmed |
| g − 3 | u8 | phase inverted (id 0–5) | confirmed |
| g − 2 | u8 | 48V (id 0–3) | confirmed (Ch 1–4) |
| g | f32 | gain dB | confirmed |
| g + 4 | f32 | compressor 0…1 | confirmed |
| g + 8 | u16 | low cut in **Hz** (20–600); id 0–5 only, on USB/BT (id 6) the bytes 1912 and 1924–1925 have no known function | confirmed, measured |
| g + 12 + 4k | f32 | PEQ band k gain dB (k = 0–3) | confirmed |
| g + 28 + 2k | u16 | PEQ band k frequency Hz (defaults 100 / 500 / 2000 / 12000) | confirmed |
| g + 36 + 4k | f32 | PEQ band k Q; 0 = shelf on bands 0 and 3 | confirmed |

**Bus block** b = 1972 + 100·(id − 10): MON 1 1972, MON 2 2072, MAIN 2472. FX 1 / FX 2 also have an EQ block (2172 / 2272) that MIDI can change, but it has no audible effect.

| Offset | Type | Content | Status |
|---|---|---|---|
| b − 4 | f32 | limiter dB (−30…0) | confirmed |
| b + 4k | f32 | GEQ band k gain dB (k = 0–8) | confirmed |
| b + 36 + 2k | u16 | GEQ band k frequency (defaults 63 … 16000, octave steps) | confirmed |
| b + 56 + 4k | f32 | GEQ band k Q (0…19.7; 0 allowed, as in the app) | confirmed |
| b + 92 | u16 | delay in samples at 48 kHz | confirmed |

**FX block** o = 2578 + 7·k (k = 0 FX 1, 1 FX 2)

| Offset | Type | Content | Status |
|---|---|---|---|
| o, o+1, o+2 | u8 | parameter 1 (0–100), parameter 2 (0/1), parameter 3 (0–100 via MIDI CC 3) | 1, 2 confirmed; 3 meaning open |
| o + 3 | u8 | preset, **1-based** | confirmed |
| o + 4…6 | u8 | routed to Main / Mon 1 / Mon 2 | Main, Mon 1 confirmed; Mon 2 pattern |
| 2576 | u16 | FX tempo BPM | confirmed |

**Settings**

| Offset | Content | Status |
|---|---|---|
| 2569 | USB/BT playback: 1 = phones only, 0 = main mix | confirmed |
| 2593 | Monitor 1/2 source: 0 monitor mix, 1 USB 1/2, 2 USB 3/4 | confirmed |
| 2603 | Ch 5/6 source: 1 = USB, 0 = local jacks | confirmed |
| 2604 | Ch 7/8 source: 1 = USB, 0 = local | confirmed |
| 2605 | monitor stereo link | confirmed |
| 2606 | headphone source: 1 = monitor, 0 = main | confirmed |
| 2608 | main −10 dBV pad | confirmed |
| 2609 | monitor −10 dBV pad | confirmed |
| 2611 | monitor tap point: 1 = post, 0 = pre | confirmed |
| 2607, 2610, 2612–2614 | unknown flags (watched by the alarm) | open |

**Not decoded:** footswitch mode, the rest of the header. Preset names are not in the dump; the page uses the names from the FLOW app (§3).

## 5 Bluetooth LE protocol

**Connection** (library, verified in use)

| Item | Value |
|---|---|
| Device name | starts with `FLOW` |
| Service UUID | `14839ad4-8d7e-415c-9a42-167340cf2339` |
| Characteristic | `0034594a-a8e7-4b1a-a6b1-cd5243059a57` (reports write + notify, but has **no descriptors**, see below) |
| Other characteristics | `0035594a-…` and `0036594a-…`: read only, constant 2 bytes (`09 00`, `E5 2D`; probably protocol version and firmware build) |
| Login | `39 01 FD 06 2B 06 39 F1 7F E7 B7 27 8B 8F 35 5A 49 5C 2A` (static key; same on every unit: open) |
| Session start | `37 01 38` |
| Snapshot names request | `07 01 08` → notification type `0x27` (not usable in the browser, not sent) |
| Dump request | `4B 01 4C` → SysEx dump on USB MIDI (confirmed) |

**Packet:** `[type, 0x01, payload…, checksum]`, checksum = sum of all previous bytes mod 256. Multi-byte values are **big-endian**. The FLOW 8 accepts only **one** BLE central at a time; USB MIDI keeps working alongside.

**No receiving in the browser (confirmed on Windows / Edge):** none of the three characteristics has a descriptor, in particular no CCCD (`0x2902`). Web Bluetooth (and Windows) can therefore not subscribe: `startNotifications()` fails with *GATT Error: Not supported*. The Android app gets the FLOW 8's replies anyway, because it only enables notifications locally (`setCharacteristicNotification`) without writing a CCCD. Consequence for this page: Bluetooth is **send only**; the state comes from the USB MIDI dump. The page does not try to subscribe and does not request snapshot names.

**Replies the app receives** (known from the app, not receivable in the browser): `0x36` = login confirmed. `0x27` = snapshot names: up to 15 entries, each with a length byte.

**Meters and gain reduction** (from the app's native library; not usable in the browser for the reason above):

| Type | Direction | Payload |
|---|---|---|
| `0x21` MeterRequest | app → mixer | 1 byte count (7, or 8 with an output selected) + 15 channel bytes: `40 41 42 43 C4 C5 C6`, then the selected output (`id \| 0x40`, `\| 0x80` if stereo), rest `00`. Sent when connecting and when an output is selected. `0x80` = stereo (two values); meaning of `0x40` open |
| `0x22` MeterUpdate | mixer → app | 15 level bytes (same fader-index format as command `0x06`, 12 used: ch 1–4, 5/6 L/R, 7/8 L/R, USB/BT L/R, output L/R) + gain reduction u16: 2 bits per channel, values 0–3; ch 1–7 in bits 0–13 (2·index), the selected output (limiter) in bits 14–15 |

The app redraws meters and the gain-reduction ring every 100 ms from the last values received; the level ballistics are computed in the app, the gain-reduction step (0–3) is shown as received.

**Commands** (encoding from the library, values per §6)

| Type | Payload | Function |
|---|---|---|
| `0x00` | id, pan code | pan / balance |
| `0x01` | id, 0/1 | solo |
| `0x02` | id, gain code | input gain |
| `0x03` | id, band 0–8, freq u16, Q code, EQ code | bus GEQ band |
| `0x04` | id, on 0/1, **Hz** u16 | low cut (value = Hz, measured: identical to the dump value) |
| `0x06` | src, dst, fader index 0–255 | send level; src = dst → master fader; 9→9 headphones |
| `0x08` | id, 0/1 | mute (inputs and buses) |
| `0x09` | id, band 0–3, freq u16, Q code, EQ code | channel PEQ band |
| `0x10` | id, 0/1 | phase |
| `0x11` | id, p1, p2, p3, enable bits (1 Main, 2 Mon 1, 4 Mon 2) | FX parameters and routing |
| `0x13` | id, 0–255 | compressor |
| `0x14` | id, gain code | limiter |
| `0x15` | id, 0/1 | 48V (only by hand, with confirmation) |
| `0x20` | slot 1–15 | load snapshot (slot numbering unverified; 16 never sent) |
| `0x25` | setting id, 0x01, value | global setting (table below) |
| `0x31` | id, preset **0-based** | FX preset |
| `0x40` | BPM u16 | FX tempo |
| `0x4A` | id, samples u32 | delay (confirmed) |

**Settings `0x25`** (ID mapping from the library; values checked against the dump)

| ID | Setting |
|---|---|
| 7 | USB/BT playback: 1 = phones only, 0 = main mix |
| 8 | monitor 1/2 source: 0 / 1 / 2 |
| 9 | Ch 5/6 → USB 1/2 |
| 10 | Ch 7/8 → USB 3/4 |
| 11 | monitor stereo link |
| 12 | headphone source: 1 = Mon 1/2, 0 = Main |
| 13 | monitor tap point: 1 = post, 0 = pre |
| 14 | main −10 dBV pad |
| 15 | monitor −10 dBV pad |

## 6 Conversions and curves

**MIDI (7-bit)**

| Parameter | dB → value | value → dB | Range |
|---|---|---|---|
| Level (sends, master) | 0 if ≤ −143 dB, else `round((dB+70)/80·126)+1` | 0 → −∞, else `(v−1)/126·80−70` | −70…+10 dB (confirmed) |
| Gain (CC 8) | `round((dB+20)/80·127)` | `v/127·80−20` | −20…+60 dB (confirmed) |
| EQ gain | `round(64+dB·63/15)`, clamp 1–127 | `(v−64)·15/63` | ±15 dB (per docs) |
| Limiter (CC 8 on bus) | `round((dB+30)/30·127)` | `v/127·30−30` | −30…0 dB (per docs) |
| Pan / balance | `round(64+pan·63)`, pan −1…+1 | `(v−64)/63`, limited to −1…+1 | (confirmed, incl. MON and FX buses) |
| EQ frequency (CC 21–29) | `round(127·log(Hz/20)/log(1000))` | `20·1000^(v/127)`, mostly rounded down (±1 Hz) | 20 Hz…20 kHz (confirmed, all channels) |
| EQ Q (CC 31–39) | `round(Q·127/19.7)` | `v·19.7/127` | 0…19.7 (confirmed, all channels) |
| FX parameter 3 (CC 3) | value | `min(v, 100)` | (dump confirmed) |
| Compressor | percent 0–100 | | (confirmed) |

**Low cut (CC 9).** The measured table in `flow8-lowcut-mapping.csv` is authoritative. It follows

```
Hz(CC) = floor(20 · 30^(CC/127))        CC 0 → 20 Hz, CC 64 → 111 Hz, CC 127 → 600 Hz
```

for 127 of 128 values. The exception is CC 92, which gives 234 Hz instead of 235. To set a frequency over MIDI, the page sends the CC whose table value is nearest. Over BLE and in the dump the value is simply Hz, so Bluetooth reaches every Hz exactly.

**BLE codes** (library)

| Parameter | Encoding |
|---|---|
| Fader | index 0–255 from `flow8-fader-tabelle.csv`: largest index whose table value ≤ dB |
| Pan | `trunc(clamp(pan,−1,1)·127 + 127)` |
| Gain, limiter | `round((clamp(dB,−60,60)+60)·2)` |
| EQ gain | `round(clamp(dB,−15,15)/15·127 + 127)`, 127 = 0 dB |
| Q | Q ≤ 0 → 0 (shelf). Q < 10.7 → `clamp(round((Q−0.3)·10)+1, 1, 101)`. Else `clamp(round(Q−11)+102, 102, 255)` |
| Compressor | `trunc(clamp(x,0,1)·255)` |

**BLE fader table shape:** a piecewise-linear dB scale, finest around 0 dB. Exact values are in the CSV.

| Index | dB | Step |
|---|---|---|
| 0 | −∞ (−144) | |
| 1–16 | −88.1 … −60.0 | ≈ 1.88 dB |
| 17–64 | −59.3 … −29.9 | ≈ 0.63 dB |
| 65–128 | −29.6 … −9.9 | ≈ 0.31 dB |
| 129–191 | −9.8 … 0.0 | ≈ 0.16 dB |
| 192–255 | +0.1 … +10.0 | ≈ 0.16 dB |

**Delay:** samples at 48 kHz.

```
ms = samples / 48          m = ms · 0.343   (speed of sound 343 m/s)
```

The UI accepts samples, ms or m and rounds to whole samples (max 65535 ≈ 1365 ms).

## 7 Audio: meters and RTA

- **Source:** the FLOW 8 USB recording tracks, listen-only. Nothing is played back and nothing is sent to the mixer. The analysis runs on Windows via `start-mixer.bat`.
- **Windows devices:** Windows exposes the FLOW 8 as seven devices (Mic 1, Mic 2, Mic/Line 3, Mic/Line 4, Line 5/6, Line 7/8, Main L/R) plus *Multi In 1-10*. Chromium returns at most 2 channels per device, so the page opens the seven single devices in parallel. That gives 10 tracks.
- **Fallback:** if fewer than 3 single devices are found, the page opens one device and takes as many channels as it gets.
- **Firefox feeder:** `flow8-audio-feeder.html` in Firefox gets all 10 tracks from *Multi In 1-10*. It posts levels and spectra to `/audio` at a fixed rate, and the page uses this source while it is fresh (< 1.5 s).
- **Default mapping** of tracks to strips:

  | Strip | Track(s) |
  |---|---|
  | Ch 1–4 | 1–4 |
  | Ch 5/6 | 5,6 |
  | Ch 7/8 | 7,8 |
  | Main | 9,10 |

  It can be changed in the Audio window.
- **Meters:** sample peak per frame. Fast attack, release 0.7 dB/frame. Peak hold for 1.5 s, then it falls 0.6 dB/frame. Scale −80…0 dBFS.
- **RTA:**
  - **Tap point:** the RTA (and the meters) show the signal where the FLOW 8 taps its USB recording tracks: input channels right after the gain stage, without low cut and EQ; main without the main EQ.
  - `AnalyserNode` with FFT 4096 / 8192 / 16384 and smoothing 0.5 / 0.8 / 0.92 (fast / medium / slow).
  - Stereo strips are power-averaged.
  - Display range 60 / 80 / 100 dB.
- **RTA modes:**

  | Mode | Bands |
  |---|---|
  | 1/3 octave | 31 ISO bands 20 Hz – 20 kHz, band edges fc / 1.1225 … fc · 1.1225, summed power |
  | 1/12 octave | 119 bands, fc = 1000 · 2^(k/12), k = −67…51, edges ±1/24 octave |
  | Fine | continuous line, maximum per pixel column |

- **Tilt:** `tilt · log2(f/1000)` dB, pivot 1 kHz.
  - Band modes sum power, so pink noise is flat at 0 dB/oct and white noise rises +3 dB/oct.
  - In fine mode white noise is flat, so pink noise is flat at +3 dB/oct.
  - The tilt menu labels the matching “flat” option for each mode.
- **AGC:** shifts the display so that the power-weighted mean of the third-octave bands sits on the EQ 0 dB line, without the highest peak passing the top edge. Time constants: 0.2 s down, 3 s up. Active only if a band exceeds −75 dBFS. In 1/12-octave mode the values are normalized to third-octave bandwidth, so pink noise also reads 0 dB there.
- **On tablets:** the PC analyses every track with the same FFT size and smoothing as its own RTA (one extra `AnalyserNode` per track, read every 40 ms whatever the network does, so the smoothing behaves the same) and sends the result (§10). The tablet draws it with the same code (`rtaPaint`), so both look alike. With the Firefox feeder active, the feeder data are passed on (fixed FFT 8192, ~12 frames/s).
- **RTA Source Main** (Ch 5/6 and 7/8): shows tracks 9/10 instead of the strip's own tracks, offset by −(send to Main) dB. The main fader is ignored, and AGC replaces the offset.

## 8 EQ display and detail tabs

- **Filters:** curves use RBJ “Audio EQ Cookbook” biquads at 48 kHz.
  - PEQ bands are peaking filters.
  - Q is continuous 0…10.7. Q = 0 is a shelf only on the outer bands (PEQ bands 0 and 3, GEQ bands 0 and 8; the GEQ shelf is drawn only, not verified on the mixer). Other bands with Q = 0 are drawn with the smallest Q the current route can send (`qMin`: MIDI CC 1 = 0.16, BLE code 1 = 0.3).
  - The sum of all bands is drawn over 20 Hz – 20 kHz (log), ±18 dB.
  - **Low cut** (channels, when on) is added to the curve as a high-pass: `−10·log10(1 + (fc/f)^(2n))` with n = slope / 6. The slope is **provisional 12 dB/octave** (`LC_SLOPE`), the real value is still to be measured. It also appears in the small EQ tiles of the strips.
- **Editing:**
  - Drag a point: frequency (x) and gain (y). Over MIDI, frequency and Q snap to the 128 CC steps; over BLE they are exact.
  - Mouse wheel on a point: Q × 1.1 per step, Shift for fine steps (`qStep`). Below `qMin` it jumps to 0, from 0 upwards to `qMin`; over MIDI every step moves at least one CC step. The point under the mouse becomes the selected band.
  - **Selected band** (`EQSEL`): clicking / tapping a point selects it; it is drawn larger with a larger number and stays selected until another point is chosen. Opening a channel or bus (`select()`) clears the selection.
  - Double-click: reset to gain 0, Q 1 (shelf bands Q 0), factory frequency.
  - Number fields accept wheel and vertical drag. Frequency moves in 1/12-octave steps (1/48 with Shift).
  - Touch (tablet): the same as dragging with the mouse. **Pinch** with two fingers changes Q of the selected band (or the band already held; nothing happens without a selection): spreading = wider curve (Q ÷ ratio), down to 0 (shelf on outer bands), pinching = narrower; from 0 it starts at `qMin`. Frequency and Q go over MIDI or BLE like on the PC.
- **Low cut control** (EQ tab, channels 1–6): slider 0…1000 mapped logarithmically to 20…600 Hz (`hz = 20·30^(pos/1000)`), so equal travel means equal octaves. The number field is exact to 1 Hz; the on/off button sends the value of the number field.

### Detail tabs (layout)

- **Channel tabs:** All Parameters, EQ, Dynamics, Sends, Raw Bytes.
  - **EQ:** curve with RTA, band table, low cut row below the table.
  - **Dynamics:** left the gain knob (−20…60 dB, 0.1 dB per px) with a tall input meter; next to it the compressor knob (0…100 %, 0.25 % per px) with its transfer curve (same drawing as the strip tile); right two large buttons: phase and 48V (ch 1–4) or USB routing (ch 5/6, 7/8). Double-click / double-tap on a knob resets it (gain 0 dB, compressor 0 %).
  - **Sends:** wider sliders (up to 460 px or half the screen). On tablets they work relatively like the faders (see §10).
- **Output tabs (MAIN, MON 1/2):** 9-band EQ; Limiter & Delay with the output meter, the limiter knob (−30…0 dB, 0.075 dB per px, double-tap = 0 dB) and its curve. Delay: samples / ms / m fields next to the limiter in one box with a delay knob (PC and tablet; linear, 3.2 samples per px ≈ 15 px per ms, `DLY_PER_PX`, double-click / double-tap = 0). MON 1/2 have no USB track, so their meter stays empty.
- **Effect tab (FX 1/2):** presets show the names from the FLOW app (`FX_PRESETS`). Parameter 1 is labelled with its preset name (`fxNice`: DECAY → Decay) and has a number field (%). Parameter 2 is called *Variant*: a left/right switch between the two value names of the preset (left = A = 0, right = B = 1). Parameter 3 (0–100) goes over MIDI CC 3 or BLE. Returns to MON 1/2 take typed dB values like the sends. Tempo row (BPM + tap) only on FX 2, disabled for presets 13–16. MIDI uses channels 14 / 15.
- **Bus strips:** every bus has a balance control. MAIN goes over MIDI or BLE; MON 1/2 and FX 1/2 only over MIDI CC 10 (red). The bus whose sends the channel faders show (`selMix`, sends on fader) has the label *SOF Target* (`sof_target`) in the top row where channels have 48V / phase / HPF; long translations wrap to two lines inside the 24 px row.
- Knobs: `knob(min, max, val, fmt, onInput, kind, perPx, def)`; `def` enables the double-click / double-tap reset.

## 9 Language files

- **Location and format:** one UTF-8 text file per language in `languages/`. The first entry is `language:<name as shown in the menu>`. After that, one `key:text` per line; only the first colon separates.
- **Syntax:**
  - Lines starting with `#` are comments.
  - `{name}` placeholders are filled by the page.
  - `\n` is a line break.
  - `**bold**` is only used in `overlay_text`.
- **Special keys:**
  - `decimal_sep` sets the decimal separator for RTA labels.
  - `language_code` sets `<html lang>`.
- **Safety:** files are parsed as data and inserted with `textContent` only. They are never executed and never interpreted as HTML.
- **Lookup order** for a key: selected language → built-in English → the key itself.
- **Built-in English:** a copy of `en.txt` is embedded in the HTML (`<script type="text/plain" id="lang-en">`), so `file://` works. When `en.txt` changes, update the embedded copy too.
- **Discovery:**
  - With the server, `/languages` lists the folder.
  - Without it, only English and files opened via *Load Language File…* (stored in `localStorage`) are available.
  - The menu sorts by native name: Latin script first, then other scripts.
  - Default: saved choice, else `en.txt`.

## 10 Tablet interface

The same page, opened from another device through the computer's network address (`http://<ip>:8000/…`), runs as a **remote**. The page decides this from `location.hostname`: anything other than `localhost`, `127.0.0.1` or `[::1]` is a remote (`REMOTE`; the PC page served by the server is `LANPC`).

```
 Tablet page ──POST /r/cmd──► server ──GET /r/cmd──► PC page ──MIDI/BLE──► FLOW 8
      ▲                                                  │
      └── GET /r/state (long poll), /r/audio?ev=1 (stream) ◄── server ◄── POST ──┘   (dump, route, RTA settings, levels/RTA)
```

**Tablet view** (default on remotes; *Full View* switches to the normal page, stored in `flow8.view`; the header button *Tablet View* switches back)

- **Mixer view:** mix tabs MAIN / MON 1 / MON 2 / FX 1 / FX 2 (`selMix`), all 7 channels plus the master of the selected mix, without scrolling. Strip from top: name (opens the channel view), pan (MAIN mix only; the master strip shows the balance of the selected bus: MAIN over MIDI or BLE, MON and FX over MIDI; double-tap = center), fader with meter and scale, dB value, mute / solo.
- **Relative faders and pan:** touching changes nothing, only movement counts; the full range needs `TB_FINE` = 2 track lengths (fader in CC steps 0…127, pan −1…1). Each pointer is captured separately, so several faders can move at once. While a fader is held, incoming state does not move it.
- **Channel view:** the normal detail area (`#detail`) is moved into a full-screen page with a back button (*← Mixer*); it opens on *All Parameters*; chips and tabs work as on the PC (§8a).
- **Top bar:** *RTA* (settings window, see below), *Global* (the normal Global window), *Fullscreen* (Fullscreen API, `webkit` prefix supported; hidden where the API is missing, e.g. iPhone), *Full View*.
- **Sends on the channel page:** `relRange()` wraps the range input: the input itself takes no pointer events, the wrapper converts horizontal movement into value changes (full range = 2 × slider width).
- **RTA settings window:** the same controls as in the PC's Audio window (`auRtaSettings`). Keys `rta, agc, mode, avg, tilt, range, fft, mainRta` are synced both ways: the PC sends them in the state (`a`), a tablet sends changes as a command `{"a":{…}}`. After its own change a tablet ignores incoming values for 2.5 s and then applies the latest, so the two never fight. The PC validates every value (`rtaValid`).
- **Full view on a remote:** the PC page minus MIDI/Bluetooth/audio controls; below 700 px width the header, panels and detail area are compacted.

**Transport**

- **Commands:** `sendMidi` / `bleSend` on a remote queue `{"m":[bytes],"l":label}` / `{"b":[bytes],"k":key,"l":label}` (RTA settings: `{"a":{…}}`). Same control within 30 ms: the last value wins. Then one `POST /r/cmd`. The *Sending enabled* checkbox on the device blocks its own output; on the PC it blocks everything.
- **State:** long poll `GET /r/state?v=N`. JSON: `d` (last dump, base64, 3068 bytes), `m` (route for “both” controls), `o` / `b` (PC has a MIDI output / BLE connection), `s` (snapshot names), `a` (RTA settings). The dump goes through the normal `finalizeDump`, including “discard while operating”; a discarded dump is applied as soon as the device is idle. The PC posts after every new dump and when anything else changes (checked every second).
- **Levels and RTA:** the PC computes a frame every 40 ms while a device was seen in the last 15 s (feeder data if active, else its own per-track analysers) and posts it as soon as the previous post has finished. Frame: `{"id","n","map","b"}`; `b` is base64 of `n × 232` bytes: per track 1 byte level, 200 bytes spectrum (log points 20 Hz–20 kHz), 31 bytes third-octave bands; 1 byte = 0.5 dB (`0` = −127.5 dB … `255` = 0 dB). About 3 KB per frame for 10 tracks. The tablet receives the frames via `EventSource('/r/audio?ev=1')`, polling `/r/audio` every 40 ms only if `EventSource` is missing.
- **PC page:** long-polls `/r/cmd` and executes each line through the normal `sendMidi` / `bleSend`. Log lines are prefixed “Phone/tablet:”.

**Command check on the PC** (also done on the device before sending):

| Accepted | Refused as “only on the PC” | Everything else |
|---|---|---|
| MIDI CC (`Bn`, 3 bytes, incl. CC 12 = 48V), Program Change `C0`–`CE` (FX presets), `9F` (tap tempo); BLE packets with valid checksum of types `00 01 02 03 04 06 08 09 10 11 13 14 15 25 31 40 4A`; RTA settings with valid values | `CF` (snapshot), BLE `20` (snapshot) | refused (SysEx, other status bytes, bad checksums) |

**Remote window** (PC only, header button *Remote*, green outline while on): switch *Allow remote control*, default **off**; while off the server refuses every device with 403 and header `X-F8: off` (the tablet shows “switched off on the PC”), and switching off closes the open event streams and waiting state requests at once. For every address the window draws a **QR code** (built-in encoder: byte mode, error correction M, versions 1–10, after Project Nayuki, MIT) that opens exactly that address including `?code=`.

**Access code** (Remote window): default *required*. The code is 6 characters (A–Z without I/O, 2–9), made with `crypto.getRandomValues` and stored in `flow8.sec`. The page sends `"<on> <req> <code>"` (each flag `1`/`0`) to `/r/sec` at start and every 3 s. A device that calls any URL with the right `?code=` gets the cookie `f8code` (`SameSite=Strict`), so later requests need no parameter. **New Code** invalidates all cookies. Until the PC page has reported its setting, the server refuses all devices. Without a code, every device in the network gets access. Plain HTTP: the code protects against accidental access in a shared network, not against someone who can read the network traffic.

## 11 Files and tools

| File | Purpose |
|---|---|
| `flow8-mixer-ble.html` | the application (PC page and tablet interface) |
| `start-mixer.bat` | Windows launcher: starts `flow8-server.ps1` minimized |
| `flow8-server.ps1` | mini server: HTTP on port 8000 with access code for other devices, tablet relay |
| `languages/*.txt` | UI texts |
| `flow8-audio-feeder.html` | Firefox page that delivers all 10 USB tracks to the mixer page |


## 12 Limits and open questions

- **Server:** `flow8-server.ps1` is untested on real Windows.
- **Tablet interface:** tested only with a simulated server and browser. In MIDI-only operation without dumps, the PC and the devices do not learn each other's changes until the next dump.
- **BLE encodings:** most come from the library and were verified in use, not byte by byte. Values that matter are documented with their status in the protocol CSV.
- **Low cut slope:** drawn with a provisional 12 dB/octave until the real value is measured.
- **Only tested on channel 1:** low cut mapping and BLE low cut. Other channels follow the same layout. USB/BT has no low cut (tested); the page does not offer one there.
- **Unverified:** snapshot slot numbering over BLE, the meaning of FX parameter 3, Program Change above 16 on the FX channels, BLE balance for MON and FX buses (the page uses MIDI there), icon numbers, the unknown flag bytes and the header. Also unverified: whether the BLE login key is identical on every unit.
- **Not implemented on purpose:** writing state via SysEx, snapshot save/delete, reset, factory reset.
- **Tested setup:** Windows 10 with Edge. macOS and Linux are untested, and so is more than one FLOW 8 at a time.
- **Help wanted:** if the unknown-byte warning appears, a short note of what you did on the mixer helps to map the remaining bytes. Please open an issue.
