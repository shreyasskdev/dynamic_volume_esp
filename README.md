# ESP32 Dynamic Volume Adjuster + Flutter Companion App

An ambient-noise-aware Bluetooth speaker system built on the **ESP32**. It streams Bluetooth audio (`A2DP`) to an amplifier while continuously sampling room noise via an **INMP441 I2S MEMS microphone**. Every 1 second, it computes the true mean RMS noise level, compensates for the speaker's own output, and dynamically scales the speaker volume—all powered from a single 5V USB connection.

Includes a **Flutter Android companion app** that connects over Bluetooth Serial (`SPP`) simultaneously with audio playback to visualize live noise/volume telemetry and tune thresholds on the fly.

---

## Repository Structure

- `main/main.ino` — ESP32 Firmware (A2DP Sink + I2S Mic + SPP Telemetry)
- `esp_volume_app/` — Flutter Android App (Live Dashboard & Threshold Tuning)
- `README.md` — Project Documentation

---

## Hardware Requirements

* **Microcontroller:** Classic ESP32 Dev Module (with Bluetooth Classic A2DP & SPP support)
* **Microphone:** INMP441 I2S Omnidirectional MEMS Microphone
* **Amplifier:** PAM8403 5V Stereo Audio Amplifier Module
* **Speaker:** 4–8Ω, 3W Speaker
* **Power Filtering:** 470µF–1000µF Electrolytic Capacitor across `VIN (5V)` and `GND`

---

## Wiring & Pinout

### 1. INMP441 Microphone to ESP32 (`I2S_NUM_1`)
| INMP441 Pin | ESP32 Pin | Notes |
| :--- | :--- | :--- |
| **VDD** | `3V3` | **Use 3.3V only** (never 5V) |
| **GND** | `GND` | Common ground |
| **SCK** | `GPIO 32` | Serial Clock |
| **WS** | `GPIO 33` | Word Select |
| **SD** | `GPIO 34` | Serial Data (Input) |
| **L/R** | `GPIO 27` (or `GND`) | Pulled `LOW` in code to select Left channel |

### 2. PAM8403 Amplifier to ESP32 (`I2S_NUM_0` Internal DAC)
| PAM8403 Pin | ESP32 Pin | Notes |
| :--- | :--- | :--- |
| **5V (+)** | `VIN` (5V) | Place `+` leg of 1000µF capacitor here |
| **GND (-)** | `GND` | Place `-` leg of 1000µF capacitor here |
| **L (or R) Input** | `GPIO 25` | ESP32 internal DAC output |
| **Audio GND** | `GND` | Common ground |

---

## How the Algorithm Works

1. **DC-Offset Removal & RMS Calculation:** Reads 32-bit I2S audio chunks from the INMP441, removes the digital DC mean offset, and computes the chunk's Root Mean Square (RMS) amplitude.
2. **1-Second True Mean Window:** Accumulates all RMS chunks over a strict `1000 ms` window and calculates the true arithmetic mean before updating the volume.
3. **Auto-Adjusting Envelope & Speaker Compensation:** Automatically tracks the room's quiet floor and loudest peaks while adding a dynamic deadzone proportional to `current_volume` so the speaker's own output does not trigger a runaway feedback loop.
4. **Dual-Mode Bluetooth (`A2DP` + `SPP`):** Streams music from the phone over Bluetooth `A2DP` while broadcasting live JSON telemetry (`{"noise":...,"vol":...}`) over `BluetoothSerial` (`SPP`) to the Flutter app without needing Wi-Fi.

---

## Setup & Installation

### 1. ESP32 Firmware (`main/main.ino`)
1. Install the following libraries in the Arduino IDE:
   * `arduino-audio-tools` by Phil Schatzmann
   * `ESP32-A2DP` by Phil Schatzmann
2. Open `main/main.ino` in the Arduino IDE.
3. Select **Board:** `ESP32 Dev Module`.
4. Set **Partition Scheme:** `Huge APP (3MB No OTA/1MB SPIFFS)`.
5. Upload to the ESP32.

### 2. Flutter Companion App (`esp_volume_app/`)
1. Pair your Android phone with **`ESP32 Speaker`** in your phone's Bluetooth settings.
2. Run `cd esp_volume_app && flutter pub get && flutter run`.
3. Grant Bluetooth permissions when prompted. The app will automatically connect to `ESP32 Speaker`, display real-time noise/volume progress bars, and let you toggle **Auto-Range** or customize **Quiet / Loud / Min / Max** volume bounds live.
