# Simplified PCIe Gen 6 Digital Model

## Overview
This project presents a structured, simulation-driven architectural digital model of the PCI Express (PCIe) Generation 6 protocol. Designed to bridge theoretical specifications with practical implementation, the model abstracts advanced high-speed features into a coherent digital framework. It provides a complete end-to-end communication pipeline to evaluate system behavior, latency, and throughput efficiency under realistic digital conditions.

## Team 101 Debuggers 
* Supervision:Dr. Omar Mahmoud Sabry
* **Team Members:**
  * Hossam Fawzy Abdel-moniem
  * Arwa Hany Saeed
  * Youssif Mahmoud Shapana
  * Ahmed Mohamed Sanad
  * Ahmed Alaa Gafaar

## System Architecture
The design spans three primary protocol layers across a transmitter and receiver, communicating over a behavioral digital channel with controlled error injection capabilities:

1. **Transaction Layer:** Manages TLP (Transaction Layer Packet) generation, header parsing, and end-to-end data transfer rules.
2. **Data Link Layer:** Ensures link reliability through sequence numbering, replay buffer management, and CRC-based error detection.
3. **Physical Layer (Digital Model):** Abstracts analog signal integrity by simulating 256-byte FLIT encapsulation, lightweight Forward Error Correction (FEC) encoding/decoding, and logical PAM4 mapping.

## Key Performance Indicators (KPIs)
The simulation framework is designed to evaluate and measure the following metrics:
* **End-to-End Latency:** Cycles required for TLP transmission and recovery.
* **Throughput Efficiency:** Ratio of useful payload to total transmitted bits (accounting for FLIT framing, FEC, and PAM4 overhead).
* **Error-Correction Rate:** Effectiveness of the simplified FEC module against injected channel errors.
* **Buffer Utilization:** Stability of replay buffers under high-load traffic scenarios.

## Repository Structure
This repository adheres to standard hardware verification practices:
* `/src` (or `/rtl`): RTL source files (`.v`, `.sv`) for Transaction, Data Link, and Physical modules.
* `/tb`: Testbench files and verification environments for ModelSim.
* `/docs`: Architecture block diagrams, theoretical analysis, and design documentation.
* `/scripts`: Synthesis constraints, compilation scripts, and simulation macros.

## Build & Simulation Instructions
1. **Prerequisites:** ModelSim (or QuestaSim) is required for functional simulation.
2. **Clone the Repository:** Pull the latest version to your local environment.
3. **Compile:** Navigate to the `/tb` directory and execute the compilation scripts to build the modules located in `/src`.
4. **Run Unit Tests:** Execute individual testbenches for FLIT construction, FEC encoding, and PAM4 logical mapping.
5. **Run System Integration:** Execute the top-level testbench to monitor the complete TLP flow from the TX Transaction Layer to the RX Transaction Layer.
6. **Analysis:** Review the generated waveforms to inspect packet sequencing, valid FLIT boundaries, and fault-tolerance mechanisms.

   
## Current Project Status
* **RTL Design:** Fully completed for all individual sub-modules across the Transaction, Data Link, and Physical layers.
* **Verification:** Unit-level functional simulation has been successfully executed and validated for all independent blocks.
* **System Integration:** Currently developing and verifying the top-level module to establish the complete end-to-end PCIe Gen 6 pipeline.
* **Hardware Implementation:** Initiated the synthesis and timing analysis phases to evaluate area, power, and hardware feasibility.
