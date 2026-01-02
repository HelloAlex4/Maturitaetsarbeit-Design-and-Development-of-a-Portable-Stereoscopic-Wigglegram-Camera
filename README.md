
# Design and Development of a Portable Stereoscopic Wigglegram Camera

**Author:** Alexander Rieser

**Project Type:** Maturitätsarbeit (25/26)

**Supervisor:** Madlaina Holler

**Expert:** Patrick Habegger

## Abstract

This Maturitätsarbeit details the design, development, and implementation of a custom-built, portable stereoscopic camera capable of capturing animated wigglegrams. While the wigglegram effect has traditionally been limited to specialized analog film cameras or bulky adapters, this project represents the world's first digital wigglegram camera outside of a few private prototypes. The camera utilizes four horizontally aligned camera modules controlled by multiple processors to capture the wigglegrams. The device surpasses most of its initial goals, such as a synchronization between the first and last camera capture of less than 16 ms. This document extensively details both the technical architecture of the device and the development process. Despite multiple identified limitations like the image resolution and quality, the final product serves as a successful proof-of-concept and a baseline for further improvement.

## Project Overview

This project aims to fill a gap in the market by providing a self-contained, handheld device capable of capturing and processing digital stereoscopic images (wigglegrams) without the need for analog film or bulky adapters. The camera captures four simultaneous images from slightly different perspectives and processes them into an animated GIF that loops back and forth to create a 3D depth effect.

## Features

* **Simultaneous Capture:** Utilizes four horizontally aligned OV5640 camera modules with a synchronization delay of less than 16ms between the first and last frame.


* **Digital Workflow:** Instant preview of captured images and on-device processing of wigglegrams.


* **Portable Design:** Handheld, custom 3D-printed ABS housing with anodized aluminum covers.


* **Touchscreen Interface:** Integrated display running a Flutter-based UI for live preview, gallery browsing, and settings.


* **Battery Power:** Integrated 2-cell Li-ion battery with USB-C charging and telemetry.



## System Architecture

The device is built on a multi-PCB architecture governed by a Raspberry Pi Compute Module 4 and four STM32 microcontrollers.

### Hardware

* **Main PCB:** Acts as the central hub connecting the Raspberry Pi CM4 and the four STM32H743VIT6 microcontrollers. It manages high-speed USB communication and connects the camera modules via DCMI.


* **Power PCB:** Manages power distribution, converting battery voltage (7.2V - 7.8V) into regulated rails (5V, 3.3V, 2.8V, 1.5V). It handles USB-C power negotiation and battery charging.


* **Sensors:** 4x OV5640 Camera Modules arranged with a fixed lens-to-lens distance.



### Software Stack

The software is distributed across three primary layers:

1. **User Interface (Flutter):** Handles user interactions, live preview rendering, and the image gallery on the Raspberry Pi.


2. **Background Processes (Python/C):** Runs on the Raspberry Pi; manages camera synchronization, image processing (GIF generation), and hardware interfacing (fan control, battery monitoring).


3. **Embedded Firmware (C/C++):** Runs on the four STM32 microcontrollers; handles low-level hardware abstraction, DCMI interfacing, and image transmission via USB.


## Development & Testing

The project utilized a "fail-fast" empirical approach, prioritizing rapid physical prototyping. Testing confirmed the camera achieves a between-frame capture time of less than 16ms, ensuring sharp images even with moving subjects. The assembly features a modular design with a 3D-printed chassis and custom heat-dissipation solutions.

## License

[Attribution-NonCommercial 4.0 International]
