# SafeFall — Wearable Health Monitoring & Fall Detection System

> Real-time fall detection and vital signs monitoring wearable with IoT connectivity, ML analysis, and instant alerts.

---

## Overview

**SafeFall** is a wearable device designed to monitor the health status of users in real time. It detects accidental falls and tracks critical vital signs (SpO2 and BPM), sending instant alerts when abnormal values are detected. The system integrates embedded hardware, IoT communication, machine learning analysis, and a web dashboard — all working together end-to-end.

This project was developed as a university capstone project in Electronics Engineering.

---

## System Architecture

```
[ESP32 Wearable] → [MQTT Broker] → [MATLAB Analysis Model] → [Web App Dashboard]
                                                            → [Telegram Alert Bot]
```

---

## Features

- **Fall Detection** — Detects sudden falls using accelerometer data and triggers immediate alerts
- **SpO2 & BPM Monitoring** — Continuous real-time tracking of blood oxygen saturation and heart rate
- **Abnormal Value Alerts** — Automatic notifications when vital signs drop below safe thresholds
- **MQTT Communication** — Lightweight and reliable IoT protocol for data transmission
- **ML-Based Activity Analysis** — MATLAB model classifies user activity and detects anomalies
- **Web Dashboard** — Real-time visualization of health data through a web application
- **Telegram Bot Alerts** — Instant alert messages sent to a configured Telegram contact

---

## Repository Structure

```
SafeFall/
├── Esp32/              # Firmware for the ESP32 microcontroller (C++)
├── EntrenModelo/       # ML model training scripts (MATLAB)
├── ModeloPro/          # Production-ready ML analysis model (MATLAB)
└── App/fall-monitor/   # Web application for data visualization (JavaScript)
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Hardware | ESP32, Pulse Oximeter Sensor, Accelerometer |
| Firmware | C++ (Arduino framework) |
| Communication | MQTT Protocol |
| Data Analysis | MATLAB (Machine Learning Model) |
| Frontend | JavaScript Web App |
| Alerts | Telegram Bot API |

---

## How It Works

1. The **ESP32 wearable** continuously reads SpO2, BPM, and accelerometer data from the sensors.
2. Data is published via **MQTT** to a broker in real time.
3. **MATLAB** subscribes to the broker, processes the incoming data through a trained ML model, and classifies user activity.
4. Results are sent to the **web dashboard** for live visualization.
5. If a fall is detected or vital signs drop abnormally, an **alert is sent via Telegram** to the designated contact.


---

## Author

Electronics Engineering Student — Universidad de Ibagué, Colombia  
[GitHub Profile](https://github.com/NInoniix)

---

## License

This project is open source and available under the [MIT License](LICENSE).
