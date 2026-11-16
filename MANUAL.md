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
8. [EQ display](#8-eq-display)
9. [Language files](#9-language-files)
10. [X-Air emulation (XR12)](#10-x-air-emulation-xr12)
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
- **Local mini server:** optional. `start-mixer.bat` starts `flow8-server.ps1`: a PowerShell `HttpListener` on `http://localhost:8000/` (not reachable from the network) plus a UDP socket on port **10024** in the local network for the X-Air emulation (§10).

  | Route | Purpose |
  |---|---|
  | `/<file>` | static files from the folder (`..` blocked); `.html` as UTF-8, `.txt` as `text/plain; charset=utf-8` |
  | `/languages` | plain-text list of all file names in `languages/`, one per line |
  | `/ping` | heartbeat from the page every 5 s; the server stops 90 s after the last ping |
  | `/bye` | sent on page close (`sendBeacon`); the server stops 8 s later |
  | `/audio` | `POST` from the Firefox feeder (levels and spectra as JSON), `GET` from the page every 60 ms |
  | `/xair` | X-Air relay. `GET` waits up to 1 s and returns received UDP packets, one per line: `<from ip:port> <own ip> <base64>`. `POST` sends packets, one per line: `<to ip:port> <base64>`. 503 if port 10024 is busy |

  Why a server at all: `getUserMedia` device labels, the Firefox feeder and the language folder need a real origin. Opened as `file://`, the page still works but without audio and with only the built-in English text.
- **Browser storage:** everything is kept in `localStorage`, nothing else is stored.

  | Key | Content |
  |---|---|
  | `flow8.mode` | `midi` / `ble` – route for “both” controls |
  | `flow8.out` | name of the last MIDI output |
  | `flow8.colors` | color settings (JSON) |
  | `flow8.audio` | audio/RTA settings and track mapping (JSON) |
  | `flow8.lang` | selected language file |
  | `flow8.langfile` | language file loaded via file picker (name + text) |

- **Safety rules (by design):**
  - Nothing is sent without a user action.
  - 48V needs a confirmation dialog.
  - Snapshot 16 (reset), factory reset, snapshot save/delete and SysEx writes are not implemented.
  - The checkbox *Sending enabled* blocks all output, also from X-Air apps.
  - From X-Air apps, 48V and snapshot commands are refused.

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

**Channels** (status: per docs)

| MIDI channel | Target |
|---|---|
| 1–7 | inputs: Ch 1, 2, 3, 4, 5/6, 7/8, USB/BT (channel = ID + 1) |
| 8–12 | buses: MAIN, MON 1, MON 2, FX 1, FX 2 |
| 13 / 14 | FX slot 1 / 2 (parameters, preset) |
| 16 | global (snapshots, FX mute, tap tempo) |

**Input channels** (MIDI channel 1–7)

| CC | Function | Value | Status |
|---|---|---|---|
| 1–4 | EQ band 1–4 gain | 64 = 0 dB, ±15 dB (§6) | per docs |
| 5 | mute | 127 on / 0 off | per docs |
| 6 | solo | 127 / 0 | per docs |
| 7 | send level → MAIN | level curve (§6) | confirmed |
| 8 | gain | −20…+60 dB (§6) | confirmed |
| 9 | low cut frequency | 128 steps, 20–600 Hz (§6) | confirmed, all 128 values measured |
| 10 | pan | 1–127, 64 = center | confirmed |
| 11 | compressor | 0–100 (%) | confirmed |
| 12 | 48V phantom | 127 / 0, **channels 1 and 2 only** | per docs |
| 14–17 | send level → MON 1, MON 2, FX 1, FX 2 | level curve | per docs |

**Buses** (MIDI channel 8–12)

| CC | Function | Value | Status |
|---|---|---|---|
| 7 | master fader | level curve | confirmed |
| 8 | limiter (MAIN, MON 1, MON 2) | −30…0 dB (§6) | per docs |
| 10 | balance (MAIN) | like pan | per docs |
| 11–19 | 9-band EQ gain (MAIN, MON 1, MON 2) | 64 = 0 dB, ±15 dB | per docs |

**FX and global**

| Message | Function | Status |
|---|---|---|
| CC 1 on ch 13/14 | FX parameter 1, 0–100 % | per docs |
| CC 2 on ch 13/14 | FX parameter 2: 0 = A, 127 = B | per docs |
| Program Change on ch 13/14 | FX preset 1–16 | per docs |
| CC 1 on ch 16 | FX mute 127 / 0 | per docs |
| Program Change on ch 16 | load snapshot 1–15 (16 = reset, never sent) | per docs |
| Note On ch 16, note 0, velocity 100 | tap tempo | per docs |

**Not available over MIDI:**
- EQ frequency and Q
- phase
- low cut on/off
- 48V on channels 3/4
- delay
- FX routing and tempo
- all global settings
- bus mute/solo

These need BLE.

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
| g − 4 | u8 | low cut on (id 0–5) | confirmed |
| g − 3 | u8 | phase inverted (id 0–5) | confirmed |
| g − 2 | u8 | 48V (id 0–3) | confirmed (Ch 1–4) |
| g | f32 | gain dB | confirmed |
| g + 4 | f32 | compressor 0…1 | confirmed |
| g + 8 | u16 | low cut in **Hz** (20–600) | confirmed, measured |
| g + 12 + 4k | f32 | PEQ band k gain dB (k = 0–3) | confirmed |
| g + 28 + 2k | u16 | PEQ band k frequency Hz (defaults 100 / 500 / 2000 / 12000) | confirmed |
| g + 36 + 4k | f32 | PEQ band k Q; 0 = shelf on bands 0 and 3 | confirmed |

**Bus block** b = 1972 + 100·(id − 10) (used for MON 1, MON 2, MAIN)

| Offset | Type | Content | Status |
|---|---|---|---|
| b − 4 | f32 | limiter dB (−30…0) | confirmed |
| b + 4k | f32 | GEQ band k gain dB (k = 0–8) | confirmed |
| b + 36 + 2k | u16 | GEQ band k frequency (defaults 63 … 16000, octave steps) | confirmed |
| b + 56 + 4k | f32 | GEQ band k Q | confirmed |
| b + 92 | u16 | delay in samples at 48 kHz | confirmed |

**FX block** o = 2578 + 7·k (k = 0 FX 1, 1 FX 2)

| Offset | Type | Content | Status |
|---|---|---|---|
| o, o+1, o+2 | u8 | parameter 1 (0–100), parameter 2 (0/1), parameter 3 | 1, 2 confirmed; 3 open |
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

**Not decoded:** footswitch mode, preset names, the rest of the header.

## 5 Bluetooth LE protocol

**Connection** (library, verified in use)

| Item | Value |
|---|---|
| Device name | starts with `FLOW` |
| Service UUID | `14839ad4-8d7e-415c-9a42-167340cf2339` |
| Characteristic | `0034594a-a8e7-4b1a-a6b1-cd5243059a57` (write with response, notify) |
| Login | `39 01 FD 06 2B 06 39 F1 7F E7 B7 27 8B 8F 35 5A 49 5C 2A` (static key; same on every unit: open) |
| Session start | `37 01 38` |
| Snapshot names request | `07 01 08` → notification type `0x27` |
| Dump request | `4B 01 4C` → SysEx dump on USB MIDI (confirmed) |

**Packet:** `[type, 0x01, payload…, checksum]`, checksum = sum of all previous bytes mod 256. Multi-byte values are **big-endian**. The FLOW 8 accepts only **one** BLE central at a time; USB MIDI keeps working alongside.

**Notifications:** `0x36` = login confirmed. `0x27` = snapshot names: up to 15 entries, each with a length byte.

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
| Pan / balance | `round(64+pan·63)`, pan −1…+1 | | (confirmed) |
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
- **RTA Source Main** (Ch 5/6 and 7/8): shows tracks 9/10 instead of the strip's own tracks, offset by −(send to Main) dB. The main fader is ignored, and AGC replaces the offset.

## 8 EQ display

- **Filters:** curves use RBJ “Audio EQ Cookbook” biquads at 48 kHz.
  - PEQ bands are peaking filters.
  - Bands 0 and 3 with Q = 0 are low/high shelves.
  - GEQ bands are peaking filters with Q ≥ 0.1.
  - The sum of all bands is drawn over 20 Hz – 20 kHz (log), ±18 dB.
- **Editing:**
  - Drag a point: frequency (x, BLE only) and gain (y).
  - Mouse wheel on a point: Q × 1.1 per step, Shift for fine steps.
  - Double-click: reset to gain 0, Q 1 (shelf bands Q 0), factory frequency.
  - Number fields accept wheel and vertical drag. Frequency moves in 1/12-octave steps (1/48 with Shift).

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

## 10 X-Air emulation (XR12)

While the page runs via the server, it answers X-Air remote apps as a **Behringer XR12** (protocol: Music Tribe's *X AIR Remote Control Protocol*, OSC over UDP 10024). The server only relays packets; all logic is in the page. Any X-Air app can be used; the user chooses.

**Status:** implemented on 16 Nov 2026 and tested only against a simulated client so far. Mappings marked *assumed* still need to be checked with real apps.

**Discovery and session**

| Message | Answer |
|---|---|
| `/xinfo` | `/xinfo ,ssss <PC ip> FLOW8-Bridge XR12 1.22` |
| `/info` | `/info ,ssss V0.04 FLOW8-Bridge XR12 1.22` |
| `/status` | `/status ,sss active <PC ip> FLOW8-Bridge` |
| `/xremote`, `/xremotenfb` | client receives all changes for 10 s (renewed by repeating) |
| `/meters ,s <id> [,i ch]`, `/renew` | meter blobs to `<id>` every 50 ms for 10 s |
| `<path>` without arguments | current value: FLOW 8 state, else last value set by an app, else the XR12 default from the scene template, else a typed default |
| `/node ,s <group>` | the whole group as one text line in scene-file format, e.g. `node ,s "/ch/01/mix ON -3.5 ON +0\n"` (sent to address `node` and, to be safe, `/node`) |
| `<path> <value>` | set: mapped to MIDI/BLE like the page's own controls; others receive the change |

**Mapping**

| XR12 | FLOW 8 |
|---|---|
| `/ch/01`–`04` | channels 1–4 |
| `/ch/05`+`06`, `/ch/07`+`08`, `/ch/09`+`10` | channels 5/6, 7/8, USB/BT (reported as linked pairs via `/config/chlink`) |
| `/ch/11`, `/ch/12` | unused |
| `/ch/NN/mix/fader`, `on`, `pan` | send to MAIN, mute, pan |
| `/ch/NN/mix/01`, `02` `/level` | send to MON 1, MON 2 |
| `/ch/NN/mix/07`, `08` `/level` | send to FX 1, FX 2 (*assumed* send numbers) |
| `/ch/NN/preamp/hpon`, `hpf`, `invert` | low cut on, low cut frequency, phase |
| `/ch/NN/eq/1–4/f, g, q, type` | PEQ bands; type LShv/HShv on bands 1/4 ⇔ Q = 0 (shelf) |
| `/ch/NN/dyn/on`, `thr` | compressor amount (thr = −40 dB · amount) |
| `/headamp/01`–`08/gain` | gain; `/phantom` is read-only (refused) |
| `/-stat/solosw/NN` | solo |
| `/bus/1`, `/bus/2` | MON 1, MON 2: fader, mute, limiter (`dyn/thr`; reported as compressor with ratio 100, knee/attack/hold/release 0, mix 100 %), EQ (see below) |
| `/lr` | MAIN: fader, mute, balance (`mix/pan`), limiter (as for the buses), EQ (see below) |
| `/rtn/1`, `/rtn/2` | FX 1, FX 2 return: fader, mute, `mix/01`/`02` = return to MON 1/2 |
| `/fxsend/1`, `/fxsend/2` | fixed 0 dB (the FLOW 8 has no FX send master) |
| `/config/solo/level` | headphone level |
| `/config/buslink/1-2` | monitor stereo link |
| `/-snap/` and `/snap/` `load`, `save`, `delete`, `/-action/initall` | refused |
| other `/-action/…` (e.g. `setclock`) | accepted without effect |

**Bus EQ:** the FLOW 8 has 9 bands per bus, the XR12 6 PEQ bands. Starting at XR12 band 1, only FLOW bands with a gain ≠ 0 are shown, in order (the first 6 if there are more). Free XR12 bands show the remaining FLOW bands with gain 0, so they can be raised in the app. While a band is edited in the app (5 s), the assignment stays fixed. Type is always PEQ; frequency, gain and Q are passed on.

**RTA:** `/meters/4` carries 100 bands 20 Hz – 20 kHz (log), computed from the USB audio of the source chosen in the app (`/-stat/rta/source`, *assumed* numbering: 0–9 = channels 1–10, 31 = main). Without audio, or for other sources: −128 dB. Like the page's own RTA, input channels are measured after the gain stage without low cut and EQ, and main without the main EQ (that is where the FLOW 8 taps its USB recording tracks).

Channel names are read-only (the FLOW 8 offers no remote command for them). `/ch/09` and `/ch/10` are always named `USB BT`.

**Value conversions** (X-Air floats 0…1)

| Parameter | Conversion |
|---|---|
| Fader / send level | X32/X-Air fader law: f ≥ 0.5 → 40f − 30 dB · f ≥ 0.25 → 80f − 50 · f ≥ 0.0625 → 160f − 70 · f > 0 → 480f − 90 · 0 → −∞; 1024 steps |
| Pan | (pan + 1) / 2 |
| EQ frequency | log 20 Hz … 20 kHz |
| EQ gain | linear ±15 dB |
| EQ Q | log 10 … 0.3 |
| Low cut | log 20 … 400 Hz (*assumed*) |
| Headamp gain | linear −12 … +60 dB |
| Compressor / limiter threshold | linear −60 … 0 dB |

**Meters:** blob = int32 count + int16 values in 1/256 dB, **little-endian** (*assumed*). `/meters/1` (40 values): channels 1–12 from the USB tracks, LR post at index 36/37. `/meters/2` channels 1–12. `/meters/5` LR at 6/7. `/meters/0` one channel. All other values −128 dB.

**Scene template:** the page embeds the default scene file of an XR12 exported from X AIR Edit (`<script id="xa-scn">`). It defines every group, the order of its values and their text format. For `/node` the page takes the template line and replaces the values the FLOW 8 knows; everything else keeps the XR12 default. Text formats: on/off `ON`/`OFF`, fader `-oo` or dB with one decimal, pan `+0`/`-35`, frequency `124.7` / `1k97` / `10k02`, EQ gain `+0.00`, Q one decimal, enums by name (e.g. `PEQ`, `LShv`, `POSTEQ`).

**Groups not in the template:** `/-prefs` and `/-stat` are answered with *assumed* lines (direct values in alphabetical order, e.g. `/-prefs 48K OFF OFF 0 "FLOW8-Bridge" OFF OFF 2x2`), because an empty line is rejected by Mixing Station. Also assumed: `/-prefs/is|lan/addr|gateway|mask` (four numbers; address = the PC's own IP, gateway x.x.x.1), `/-prefs/is`, `/-prefs/lan`, `/-prefs/ap`, `/-prefs/rta`, `/-stat/rta`, `/-stat/tape`, `/-stat/usb`, `/-snap` (index, name) and `/-snap/01`–`64` (name, 59-character scope; names 1–15 from the FLOW 8, read-only), `/-stat/usb/001`–`200` (name, type: empty) and `/-stat/networks/NN` (flags, ssid, strength: empty). Other unknown groups get an empty line (only the path). Unknown paths are counted in the log (*Global → X-Air Remote → Copy Log*), which is the basis for the next iterations. The order of `/config/linkcfg` is *assumed*; `/ch/NN/preamp` (phantom via headamp, polarity, low cut) is confirmed with X AIR Edit.

## 11 Files and tools

| File | Purpose |
|---|---|
| `flow8-mixer-ble.html` | the application |
| `start-mixer.bat` | Windows launcher: starts `flow8-server.ps1` minimized |
| `flow8-server.ps1` | mini server: HTTP on localhost, X-Air UDP relay |
| `languages/*.txt` | UI texts |
| `flow8-audio-feeder.html` | Firefox page that delivers all 10 USB tracks to the mixer page |


## 12 Limits and open questions

- **X-Air emulation:** new and so far tested only against a simulated client. `flow8-server.ps1` is untested on real Windows. Assumed: FX send numbers, low-cut scale, meter byte order, the order of some values inside `/node` lines.
- **BLE encodings:** most come from the library and were verified in use, not byte by byte. Values that matter are documented with their status in the protocol CSV.
- **Only tested on channel 1:** low cut mapping and BLE low cut. Other channels follow the same layout.
- **Unverified:** snapshot slot numbering over BLE, FX parameter 3, icon numbers, the unknown flag bytes and the header. Also unverified: whether the BLE login key is identical on every unit.
- **Not implemented on purpose:** writing state via SysEx, snapshot save/delete, reset, factory reset.
- **Tested setup:** Windows 10 with Edge. macOS and Linux are untested, and so is more than one FLOW 8 at a time.
- **Help wanted:** if the unknown-byte warning appears, a short note of what you did on the mixer helps to map the remaining bytes. Please open an issue.
