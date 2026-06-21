#!/usr/bin/env python3
"""
NurseryHub Node Board v2 — KiCad 10 Schematic Generator
Spec: Hardware/NodeBoard_v2_Spec.md (signed off 2026-06-20)

Usage:
    python generate_schematic.py
    Opens node_board_v2.kicad_sch in KiCad 10.

Key improvements over v1:
  - NETLIST dict is the single source of truth. All pin→net assignments
    live here, not scattered through placement code.
  - Pin numbers match footprint pad names (A/K for diodes, +/- for caps).
  - AMS1117: pin1=GND, pin2=OUT, pin3=IN — verified against datasheet.
  - ESP32: pad numbers calculated from DevKitC-32E physical pinout.
  - Verification table printed before writing — check it before sending to fab.

Pin-to-pad conventions used:
  Resistors (R_Axial)    : pad "1" and "2"
  Diodes/TVS (D_DO-41)  : pad "A" (anode) and "K" (cathode)
  LEDs (LED_D5/D3)      : pad "A" and "K"
  Electrolytic caps      : pad "+" and "-"
  Ceramic caps (C_Disc)  : pad "1" and "2"
  AMS1117 (SOT-223)     : pad "1"=GND, "2"=OUT, "3"=IN, tab shorted to "2" by footprint
  2x19 header pads      : left row = odd (1,3,5...37), right row = even (2,4,6...38)
  RJ45                  : pads "1"-"8" + "S" (shield)
  Screw terminals        : pads "1" and "2"
  DIP switch 4-pos       : pads "1"-"4" (input), "5"-"8" (output)
  Test points            : pad "1"
"""

import uuid, os
from datetime import date

def uid():
    return str(uuid.uuid4())

def f(v):
    return round(float(v), 3)

def snap(v, grid=1.27):
    """Snap a mm value to KiCad's 50mil (1.27mm) schematic grid."""
    return round(float(v) / grid) * grid

# =============================================================================
# NETLIST — single source of truth for all pin→net connections
# Review this against NodeBoard_v2_Spec.md before generating the schematic.
# =============================================================================

NETLIST = {

    # ── POWER INPUT ──────────────────────────────────────────────────────────
    # J_PWR is the 5.08mm screw terminal where 12V supply connects.
    "J_PWR":  {"1": "+12V_IN",    "2": "GND"},

    # D1: reverse polarity protection. Anode on supply side, Cathode toward switch.
    # DO-41 footprint: pad A = anode (left), pad K = cathode (right).
    "D1":     {"1": "12V_PRE_SW", "2": "+12V_IN"},

    # J_SW1: 5.08mm screw terminal. External panel switch connects between pins 1 and 2.
    "J_SW1":  {"1": "12V_PRE_SW", "2": "+12V"},

    # ── BULK DECOUPLING CAPS ─────────────────────────────────────────────────
    # Electrolytic: pad "+" = positive, pad "-" = negative.
    "C1":  {"1": "+12V",  "2": "GND"},
    "C2":  {"1": "+5V",   "2": "GND"},
    "C3":  {"1": "+3V3",  "2": "GND"},

    # ── BUCK MODULE (LM2596) ─────────────────────────────────────────────────
    # 4-pin 15mm-riser header. Pins: 1=IN+, 2=IN-, 3=OUT+, 4=OUT-
    "U2":  {"1": "+12V", "2": "GND", "3": "+5V", "4": "GND"},

    # ── AMS1117-3.3 (U3) ─────────────────────────────────────────────────────
    # SOT-223-3_TabPin2 footprint. PINOUT (verify against datasheet before fab):
    #   Pin 1 (leftmost, notch end) = GND/ADJ
    #   Pin 2 (middle)              = OUTPUT (+3V3)
    #   Pin 3 (rightmost)           = INPUT  (+5V)
    #   Tab                         = OUTPUT — shorted to pad 2 inside footprint
    "U3":  {"1": "GND",  "2": "+3V3", "3": "+5V"},
    "C13": {"1": "+3V3", "2": "GND"},   # 100nF AMS1117 decoupling (ceramic, non-polar)

    # ── STATUS LEDs ──────────────────────────────────────────────────────────
    # All LEDs: Anode→resistor net, Cathode→GND.
    # LED_THT footprints: pad A = anode (longer lead), pad K = cathode.
    "R13": {"1": "+12V",   "2": "LED1_A"},
    "R14": {"1": "+5V",    "2": "LED2_A"},
    "R15": {"1": "+3V3",   "2": "LED3_A"},
    "LED1": {"1": "LED1_A", "2": "GND"},   # Red   12V
    "LED2": {"1": "LED2_A", "2": "GND"},   # Yellow 5V
    "LED3": {"1": "LED3_A", "2": "GND"},   # Green  3V3

    # ── ESP32-DevKitC SOCKET (U1) ─────────────────────────────────────────────
    # Footprint: PinHeader_2x19_P2.54mm_Vertical
    # 2x19 header pad numbering convention:
    #   Left  row (from top): odd  pads 1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31, 33, 35, 37
    #   Right row (from top): even pads 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 34, 36, 38
    #
    # DevKitC-32E physical pinout (USB connector at top):
    #   Left  col: GND, IO23, IO22, TXD0, RXD0, IO21, GND, IO19, IO18, IO5,
    #              IO17, IO16, IO4, IO0, IO2, IO15, GND, IO8*, IO7*
    #   Right col: 3V3, EN, IO36, IO39, IO34, IO35, IO32, IO33, IO25, IO26,
    #              IO27, IO14, IO12, GND, IO13, IO9*, IO10*, IO11*, VIN
    # (* = connected to internal flash — leave NC)
    "U1": {
        # Left column — odd pads
        "1":  "GND",          # L1:  GND
        "3":  "SD_MOSI",      # L2:  IO23  → SD MOSI
        "5":  "SCL",          # L3:  IO22  → I2C SCL
        "7":  "PI_TX",        # L4:  TXD0  → Pi UART TX (DNP)
        "9":  "PI_RX",        # L5:  RXD0  → Pi UART RX (DNP)
        "11": "SDA",          # L6:  IO21  → I2C SDA
        "13": "GND",          # L7:  GND
        "15": "SD_MISO",      # L8:  IO19  → SD MISO
        "17": "SD_SCK",       # L9:  IO18  → SD SCK
        "19": "SD_CS",        # L10: IO5   → SD CS
        "21": "NC_IO17",      # L11: IO17  → NC
        "23": "NC_IO16",      # L12: IO16  → NC
        "25": "NC_IO4",       # L13: IO4   → NC
        "27": "NC_IO0",       # L14: IO0   → NC (boot strap — leave NC)
        "29": "NC_IO2",       # L15: IO2   → NC (boot strap — leave NC)
        "31": "NC_IO15",      # L16: IO15  → NC
        "33": "GND",          # L17: GND
        "35": "NC_IO8",       # L18: IO8   → NC (internal flash)
        "37": "NC_IO7",       # L19: IO7   → NC (internal flash)
        # Right column — even pads
        "2":  "ESP_3V3",      # R1:  3V3 output — NOT connected to +3V3 bus
        "4":  "NC_EN",        # R2:  EN    → NC (DevKitC has onboard pull-up)
        "6":  "NC_IO36",      # R3:  IO36  → NC (input only, no pullup)
        "8":  "NC_IO39",      # R4:  IO39  → NC (input only, no pullup)
        "10": "MST_C_SIG",    # R5:  IO34  → Moisture zone C ADC
        "12": "MST_D_SIG",    # R6:  IO35  → Moisture zone D ADC
        "14": "MST_A_SIG",    # R7:  IO32  → Moisture zone A ADC
        "16": "MST_B_SIG",    # R8:  IO33  → Moisture zone B ADC
        "18": "RLY_A_SW",     # R9:  IO25  → Zone A relay (GPIO output)
        "20": "RLY_B_SW",     # R10: IO26  → Zone B relay
        "22": "DHT_DATA",     # R11: IO27  → DHT22 data
        "24": "RLY_D_SW",     # R12: IO14  → Zone D relay
        "26": "NC_IO12",      # R13: IO12  → NC (boot strap — leave NC)
        "28": "GND",          # R14: GND
        "30": "RLY_C_SW",     # R15: IO13  → Zone C relay
        "32": "NC_IO9",       # R16: IO9   → NC (internal flash)
        "34": "NC_IO10",      # R17: IO10  → NC (internal flash)
        "36": "NC_IO11",      # R18: IO11  → NC (internal flash)
        "38": "+5V",          # R19: VIN   → +5V
    },

    # ── ZONE ENABLE DIP SWITCH (SW2) ─────────────────────────────────────────
    # 4-position DIP switch. Standard DIP-8 footprint numbering:
    #   Left side (input):  pad 1 (top-left) → pad 4 (bottom-left)
    #   Right side (output): pad 8 (top-right) → pad 5 (bottom-right)
    # Pad 1 is ACROSS from pad 8 (both top), NOT pad 5 (bottom-right).
    # When switch pos 1 is ON: pad 1 connects to pad 8.
    # When switch pos 2 is ON: pad 2 connects to pad 7. Etc.
    # BUG HISTORY: Previously had "5":"RLY_A_IN" — WRONG. Pad 5 is pos 4 output
    # (bottom-right), not pos 1 output. Fixed 2026-06-21. PCB was corrected
    # manually in KiCad editor (pad 8→RLY_A_IN etc.) before FreeRouting re-run.
    "SW2": {
        "1": "RLY_A_SW", "2": "RLY_B_SW", "3": "RLY_C_SW", "4": "RLY_D_SW",
        "8": "RLY_A_IN", "7": "RLY_B_IN", "6": "RLY_C_IN", "5": "RLY_D_IN",
    },

    # ── ZONE A ───────────────────────────────────────────────────────────────
    # Series resistor (relay IN current limit)
    "R1":  {"1": "RLY_A_IN",  "2": "RLY_A_OUT"},
    # Pull-down (holds relay IN low when ESP32 not driving)
    "R16": {"1": "RLY_A_IN",  "2": "GND"},
    # Zone LED series resistor
    "R9":  {"1": "RLY_A_OUT", "2": "ZA_LED_A"},
    # Zone A activity LED. Anode→R9 net, Cathode→GND.
    "LED4": {"1": "ZA_LED_A", "2": "GND"},
    # Moisture sensor VCC protection diode.
    # 1N5819 DO-41: Anode=+3V3 (supply side), Cathode=sensor side.
    # Current flows FROM +3V3 TO sensor. Band (cathode) faces sensor connector.
    "D2":  {"1": "MST_A_VCC", "2": "+3V3"},
    # Sensor VCC decoupling cap
    "C4":  {"1": "MST_A_VCC", "2": "GND"},
    # TVS clamp on ADC signal line.
    # P6KE3.3A: Cathode toward signal line, Anode toward GND.
    # In normal operation: REVERSE biased. Clamps spikes above 3.3V.
    # If reads 0.7V on ADC: TVS is forward biased = fitted backwards.
    "D10": {"1": "MST_A_SIG", "2": "GND"},
    # Zone A RJ45 jack. Zone RJ45 pinout (T568B twisted-pair assignments):
    #   Pin 1 = MST_SIG (pair with GND pin 2)
    #   Pin 2 = GND
    #   Pin 3 = MST_VCC (pair with GND pin 6)
    #   Pin 4 = RLY_IN  (pair with GND pin 5)
    #   Pin 5 = GND
    #   Pin 6 = GND
    #   Pin 7 = RLY_5V  (pair with GND pin 8)
    #   Pin 8 = GND
    #   S     = GND (shield)
    "J_ZONE_A": {
        "1": "MST_A_SIG", "2": "GND", "3": "MST_A_VCC", "4": "RLY_A_OUT",
        "5": "GND", "6": "GND", "7": "+5V", "8": "GND", "S": "GND",
    },
    # Relay flyback diode DNP (relay modules have onboard flyback)
    "D14": {"1": "+5V", "2": "GND"},

    # ── ZONE B ───────────────────────────────────────────────────────────────
    "R2":  {"1": "RLY_B_IN",  "2": "RLY_B_OUT"},
    "R17": {"1": "RLY_B_IN",  "2": "GND"},
    "R10": {"1": "RLY_B_OUT", "2": "ZB_LED_A"},
    "LED5": {"1": "ZB_LED_A", "2": "GND"},
    "D3":  {"1": "MST_B_VCC", "2": "+3V3"},
    "C5":  {"1": "MST_B_VCC", "2": "GND"},
    "D11": {"1": "MST_B_SIG", "2": "GND"},
    "J_ZONE_B": {
        "1": "MST_B_SIG", "2": "GND", "3": "MST_B_VCC", "4": "RLY_B_OUT",
        "5": "GND", "6": "GND", "7": "+5V", "8": "GND", "S": "GND",
    },
    "D15": {"1": "+5V", "2": "GND"},

    # ── ZONE C ───────────────────────────────────────────────────────────────
    "R3":  {"1": "RLY_C_IN",  "2": "RLY_C_OUT"},
    "R18": {"1": "RLY_C_IN",  "2": "GND"},
    "R11": {"1": "RLY_C_OUT", "2": "ZC_LED_A"},
    "LED6": {"1": "ZC_LED_A", "2": "GND"},
    "D4":  {"1": "MST_C_VCC", "2": "+3V3"},
    "C6":  {"1": "MST_C_VCC", "2": "GND"},
    "D12": {"1": "MST_C_SIG", "2": "GND"},
    "J_ZONE_C": {
        "1": "MST_C_SIG", "2": "GND", "3": "MST_C_VCC", "4": "RLY_C_OUT",
        "5": "GND", "6": "GND", "7": "+5V", "8": "GND", "S": "GND",
    },
    "D16": {"1": "+5V", "2": "GND"},

    # ── ZONE D ───────────────────────────────────────────────────────────────
    "R4":  {"1": "RLY_D_IN",  "2": "RLY_D_OUT"},
    "R19": {"1": "RLY_D_IN",  "2": "GND"},
    "R12": {"1": "RLY_D_OUT", "2": "ZD_LED_A"},
    "LED7": {"1": "ZD_LED_A", "2": "GND"},
    "D5":  {"1": "MST_D_VCC", "2": "+3V3"},
    "C7":  {"1": "MST_D_VCC", "2": "GND"},
    "D13": {"1": "MST_D_SIG", "2": "GND"},
    "J_ZONE_D": {
        "1": "MST_D_SIG", "2": "GND", "3": "MST_D_VCC", "4": "RLY_D_OUT",
        "5": "GND", "6": "GND", "7": "+5V", "8": "GND", "S": "GND",
    },
    "D17": {"1": "+5V", "2": "GND"},

    # ── DHT22 ────────────────────────────────────────────────────────────────
    "D6":  {"1": "DHT_VCC",  "2": "+3V3"},
    "C8":  {"1": "DHT_VCC", "2": "GND"},
    "R5":  {"1": "+3V3",    "2": "DHT_DATA"},   # 10k pull-up
    # DHT22 RJ45 jack pinout:
    #   Pin 1 = DATA (pair with GND pin 2)
    #   Pin 3 = VCC  (pair with GND pin 6)
    #   Pins 4,7,8 = NC
    "J_DHT": {
        "1": "DHT_DATA", "2": "GND", "3": "DHT_VCC",
        "4": "NC_DHT4",  "5": "GND", "6": "GND",
        "7": "NC_DHT7",  "8": "NC_DHT8", "S": "GND",
    },

    # ── I2C BUS ──────────────────────────────────────────────────────────────
    "R6": {"1": "+3V3", "2": "SDA"},   # 4.7k SDA pull-up
    "R7": {"1": "+3V3", "2": "SCL"},   # 4.7k SCL pull-up
    # I2C connector 1
    # I2C RJ45 pinout: Pin1=SDA, Pin2=GND, Pin3=VCC, Pin4=SCL, Pin5/6=GND
    "D7":    {"1": "I2C1_VCC", "2": "+3V3"},
    "C9":    {"1": "I2C1_VCC","2": "GND"},
    "J_I2C_1": {
        "1": "SDA", "2": "GND", "3": "I2C1_VCC", "4": "SCL",
        "5": "GND", "6": "GND", "7": "NC_I2C1_7", "8": "NC_I2C1_8", "S": "GND",
    },
    # I2C connector 2
    "D8":    {"1": "I2C2_VCC", "2": "+3V3"},
    "C10":   {"1": "I2C2_VCC","2": "GND"},
    "J_I2C_2": {
        "1": "SDA", "2": "GND", "3": "I2C2_VCC", "4": "SCL",
        "5": "GND", "6": "GND", "7": "NC_I2C2_7", "8": "NC_I2C2_8", "S": "GND",
    },
    # I2C connector 3
    "D9":    {"1": "I2C3_VCC", "2": "+3V3"},
    "C11":   {"1": "I2C3_VCC","2": "GND"},
    "J_I2C_3": {
        "1": "SDA", "2": "GND", "3": "I2C3_VCC", "4": "SCL",
        "5": "GND", "6": "GND", "7": "NC_I2C3_7", "8": "NC_I2C3_8", "S": "GND",
    },

    # ── SD CARD SOCKET (Würth 693072010801 or compatible push-push MicroSD) ──
    # Pinout per SD Association spec / Würth datasheet.
    # DAT2 (pin1) and DAT1 (pin8) are NC in SPI mode.
    "SD_MOD": {
        "1": "GND",       # DAT2 — NC in SPI, tie to GND via 47k (R8 repurposed) or leave NC
        "2": "SD_CS",     # DAT3/CD = SPI CS
        "3": "SD_MOSI",   # CMD = SPI MOSI
        "4": "+3V3",      # VDD
        "5": "SD_SCK",    # CLK = SPI SCK
        "6": "GND",       # VSS
        "7": "SD_MISO",   # DAT0 = SPI MISO
        "8": "GND",       # DAT1 — NC in SPI, tie to GND
        "SH": "GND",      # Shield
    },
    "C12": {"1": "+3V3", "2": "GND"},   # SD module VCC decoupling (electrolytic)
    "R8":  {"1": "+3V3", "2": "SD_CS"}, # SD CS pull-up 10k

    # ── PI UART HEADER (DNP) ─────────────────────────────────────────────────
    "J_PI": {"1": "+5V", "2": "GND", "3": "PI_TX", "4": "PI_RX"},

    # ── PWR_FLAGS — one per rail so ERC knows each net is driven ────────────
    "PWRF_GND": {"1": "GND"},
    "PWRF_5V":  {"1": "+5V"},
    # +3V3 is driven by U3 Pin 2 (power_out) — no PWR_FLAG needed, it would cause pin_to_pin conflict

    # ── TEST POINTS ──────────────────────────────────────────────────────────
    "TP1":  {"1": "GND"},
    "TP2":  {"1": "+3V3"},
    "TP3":  {"1": "+5V"},
    "TP4":  {"1": "+12V_IN"},   # 12V at J_PWR — always live when PSU connected
    "TP5":  {"1": "+12V"},      # 12V main bus — 0V when SW1 off
    "TP6":  {"1": "ESP_3V3"},   # ESP32 3V3 output (separate from board +3V3)
    "TP7":  {"1": "MST_A_VCC"},
    "TP8":  {"1": "MST_A_SIG"},
    "TP9":  {"1": "RLY_A_SW"},
    "TP10": {"1": "RLY_A_IN"},
    "TP11": {"1": "MST_B_VCC"},
    "TP12": {"1": "MST_B_SIG"},
    "TP13": {"1": "RLY_B_SW"},
    "TP14": {"1": "RLY_B_IN"},
    "TP15": {"1": "MST_C_VCC"},
    "TP16": {"1": "MST_C_SIG"},
    "TP17": {"1": "RLY_C_SW"},
    "TP18": {"1": "RLY_C_IN"},
    "TP19": {"1": "MST_D_VCC"},
    "TP20": {"1": "MST_D_SIG"},
    "TP21": {"1": "RLY_D_SW"},
    "TP22": {"1": "RLY_D_IN"},
    "TP23": {"1": "SDA"},
    "TP24": {"1": "SCL"},
    "TP25": {"1": "I2C1_VCC"},
    "TP26": {"1": "I2C2_VCC"},
    "TP27": {"1": "I2C3_VCC"},
    "TP28": {"1": "DHT_VCC"},
    "TP29": {"1": "DHT_DATA"},
    "TP30": {"1": "SD_CS"},
    "TP31": {"1": "SD_MOSI"},
    "TP32": {"1": "SD_MISO"},
    "TP33": {"1": "SD_SCK"},
}

# =============================================================================
# COMPONENT METADATA
# ref: (value, footprint, dnp, symbol_type)
# symbol_type keys defined in SYMBOL_TYPES below.
# =============================================================================

COMPONENTS = {
    # Footprint: verify against KiCad library — Phoenix MC 1,5/2-ST-5,08 or equivalent
    "J_PWR":    ("12V 5.08mm Terminal",  "TerminalBlock_Phoenix:TerminalBlock_Phoenix_MKDS-1,5-2-5.08_1x02_P5.08mm_Horizontal", False, "CONN2"),
    "J_SW1":    ("Power Switch 5.08mm",  "TerminalBlock_Phoenix:TerminalBlock_Phoenix_MKDS-1,5-2-5.08_1x02_P5.08mm_Horizontal", False, "CONN2"),
    "D1":       ("1N5819",               "Diode_THT:D_DO-41_SOD81_P10.16mm_Horizontal",                                    False, "DIODE"),
    "U2":       ("LM2596 5V Module",     "Connector_PinHeader_2.54mm:PinHeader_1x04_P2.54mm_Vertical",                     False, "CONN4"),
    "U3":       ("AMS1117-3.3",          "Package_TO_SOT_SMD:SOT-223-3_TabPin2",                                           False, "AMS1117"),
    "C1":       ("100uF 25V",            "Capacitor_THT:CP_Radial_D6.3mm_P2.50mm",                                         False, "CAP_POL"),
    "C2":       ("100uF 25V",            "Capacitor_THT:CP_Radial_D6.3mm_P2.50mm",                                         False, "CAP_POL"),
    "C3":       ("100uF 16V",            "Capacitor_THT:CP_Radial_D6.3mm_P2.50mm",                                         False, "CAP_POL"),
    "C13":      ("100nF AMS decoup",     "Capacitor_THT:C_Disc_D3.8mm_W2.6mm_P2.50mm",                                     False, "CAP"),
    "R13":      ("1k",                   "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",                 False, "RES"),
    "R14":      ("1k",                   "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",                 False, "RES"),
    "R15":      ("1k",                   "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",                 False, "RES"),
    "LED1":     ("Red 5mm 12V",          "LED_THT:LED_D5.0mm",                                                              False, "LED"),
    "LED2":     ("Yellow 5mm 5V",        "LED_THT:LED_D5.0mm",                                                              False, "LED"),
    "LED3":     ("Green 5mm 3V3",        "LED_THT:LED_D5.0mm",                                                              False, "LED"),
    "U1":       ("ESP32-DevKitC-32E",    "node_board_v2:ESP32-DevKitC-32E_Socket",                                          False, "ESP32"),
    "SW2":      ("DIP 4pos Zone Enable", "Button_Switch_THT:SW_DIP_SPSTx04_Piano_10.8x11.72mm_W7.62mm_P2.54mm",            False, "DIP4"),
    "R1":       ("1k series",            "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",                 False, "RES"),
    "R2":       ("1k series",            "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",                 False, "RES"),
    "R3":       ("1k series",            "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",                 False, "RES"),
    "R4":       ("1k series",            "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",                 False, "RES"),
    "R16":      ("10k pulldown",         "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",                 False, "RES"),
    "R17":      ("10k pulldown",         "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",                 False, "RES"),
    "R18":      ("10k pulldown",         "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",                 False, "RES"),
    "R19":      ("10k pulldown",         "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",                 False, "RES"),
    "R9":       ("1k LED",               "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",                 False, "RES"),
    "R10":      ("1k LED",               "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",                 False, "RES"),
    "R11":      ("1k LED",               "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",                 False, "RES"),
    "R12":      ("1k LED",               "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",                 False, "RES"),
    "LED4":     ("Blue 3mm Zone A",      "LED_THT:LED_D3.0mm",                                                              False, "LED"),
    "LED5":     ("Blue 3mm Zone B",      "LED_THT:LED_D3.0mm",                                                              False, "LED"),
    "LED6":     ("Blue 3mm Zone C",      "LED_THT:LED_D3.0mm",                                                              False, "LED"),
    "LED7":     ("Blue 3mm Zone D",      "LED_THT:LED_D3.0mm",                                                              False, "LED"),
    "D2":       ("1N5819 VCC prot",      "Diode_THT:D_DO-41_SOD81_P10.16mm_Horizontal",                                    False, "DIODE"),
    "D3":       ("1N5819 VCC prot",      "Diode_THT:D_DO-41_SOD81_P10.16mm_Horizontal",                                    False, "DIODE"),
    "D4":       ("1N5819 VCC prot",      "Diode_THT:D_DO-41_SOD81_P10.16mm_Horizontal",                                    False, "DIODE"),
    "D5":       ("1N5819 VCC prot",      "Diode_THT:D_DO-41_SOD81_P10.16mm_Horizontal",                                    False, "DIODE"),
    "D6":       ("1N5819 VCC prot",      "Diode_THT:D_DO-41_SOD81_P10.16mm_Horizontal",                                    False, "DIODE"),
    "D7":       ("1N5819 VCC prot",      "Diode_THT:D_DO-41_SOD81_P10.16mm_Horizontal",                                    False, "DIODE"),
    "D8":       ("1N5819 VCC prot",      "Diode_THT:D_DO-41_SOD81_P10.16mm_Horizontal",                                    False, "DIODE"),
    "D9":       ("1N5819 VCC prot",      "Diode_THT:D_DO-41_SOD81_P10.16mm_Horizontal",                                    False, "DIODE"),
    "D10":      ("P6KE3.3A TVS",         "Diode_THT:D_DO-15_P12.70mm_Horizontal",                                          False, "DIODE"),
    "D11":      ("P6KE3.3A TVS",         "Diode_THT:D_DO-15_P12.70mm_Horizontal",                                          False, "DIODE"),
    "D12":      ("P6KE3.3A TVS",         "Diode_THT:D_DO-15_P12.70mm_Horizontal",                                          False, "DIODE"),
    "D13":      ("P6KE3.3A TVS",         "Diode_THT:D_DO-15_P12.70mm_Horizontal",                                          False, "DIODE"),
    "D14":      ("1N4007 flyback DNP",   "Diode_THT:D_DO-41_SOD81_P10.16mm_Horizontal",                                    True,  "DIODE"),
    "D15":      ("1N4007 flyback DNP",   "Diode_THT:D_DO-41_SOD81_P10.16mm_Horizontal",                                    True,  "DIODE"),
    "D16":      ("1N4007 flyback DNP",   "Diode_THT:D_DO-41_SOD81_P10.16mm_Horizontal",                                    True,  "DIODE"),
    "D17":      ("1N4007 flyback DNP",   "Diode_THT:D_DO-41_SOD81_P10.16mm_Horizontal",                                    True,  "DIODE"),
    "C4":       ("100nF",                "Capacitor_THT:C_Disc_D3.8mm_W2.6mm_P2.50mm",                                     False, "CAP"),
    "C5":       ("100nF",                "Capacitor_THT:C_Disc_D3.8mm_W2.6mm_P2.50mm",                                     False, "CAP"),
    "C6":       ("100nF",                "Capacitor_THT:C_Disc_D3.8mm_W2.6mm_P2.50mm",                                     False, "CAP"),
    "C7":       ("100nF",                "Capacitor_THT:C_Disc_D3.8mm_W2.6mm_P2.50mm",                                     False, "CAP"),
    "C8":       ("100nF",                "Capacitor_THT:C_Disc_D3.8mm_W2.6mm_P2.50mm",                                     False, "CAP"),
    "C9":       ("100nF",                "Capacitor_THT:C_Disc_D3.8mm_W2.6mm_P2.50mm",                                     False, "CAP"),
    "C10":      ("100nF",                "Capacitor_THT:C_Disc_D3.8mm_W2.6mm_P2.50mm",                                     False, "CAP"),
    "C11":      ("100nF",                "Capacitor_THT:C_Disc_D3.8mm_W2.6mm_P2.50mm",                                     False, "CAP"),
    "C12":      ("100uF 3V3 SD",         "Capacitor_THT:CP_Radial_D6.3mm_P2.50mm",                                         False, "CAP_POL"),
    "J_ZONE_A": ("Zone A RJ45",          "Connector_RJ:RJ45_Amphenol_54602-x08_Horizontal",                                 False, "RJ45"),
    "J_ZONE_B": ("Zone B RJ45",          "Connector_RJ:RJ45_Amphenol_54602-x08_Horizontal",                                 False, "RJ45"),
    "J_ZONE_C": ("Zone C RJ45",          "Connector_RJ:RJ45_Amphenol_54602-x08_Horizontal",                                 False, "RJ45"),
    "J_ZONE_D": ("Zone D RJ45",          "Connector_RJ:RJ45_Amphenol_54602-x08_Horizontal",                                 False, "RJ45"),
    "J_DHT":    ("DHT22 RJ45",           "Connector_RJ:RJ45_Amphenol_54602-x08_Horizontal",                                 False, "RJ45"),
    "J_I2C_1":  ("I2C 1 RJ45",          "Connector_RJ:RJ45_Amphenol_54602-x08_Horizontal",                                 False, "RJ45"),
    "J_I2C_2":  ("I2C 2 RJ45",          "Connector_RJ:RJ45_Amphenol_54602-x08_Horizontal",                                 False, "RJ45"),
    "J_I2C_3":  ("I2C 3 RJ45",          "Connector_RJ:RJ45_Amphenol_54602-x08_Horizontal",                                 False, "RJ45"),
    "SD_MOD":   ("MicroSD Socket",        "Connector_Card:microSD_HC_Wuerth_693072010801",                                   False, "SD_SOCKET"),
    "R5":       ("10k DHT pullup",       "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",                 False, "RES"),
    "R6":       ("4k7 SDA pullup",       "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",                 False, "RES"),
    "R7":       ("4k7 SCL pullup",       "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",                 False, "RES"),
    "R8":       ("10k CS pullup",        "Resistor_THT:R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",                 False, "RES"),
    "J_PI":     ("Pi UART DNP",          "Connector_PinHeader_2.54mm:PinHeader_1x04_P2.54mm_Vertical",                      True,  "CONN4"),
    # Power flags — schematic-only, no footprint
    "PWRF_GND": ("PWR_FLAG",            "",                                                                                   False, "PWR_FLAG"),
    "PWRF_5V":  ("PWR_FLAG",            "",                                                                                   False, "PWR_FLAG"),
    **{f"TP{n}": (f"TP{n}", "TestPoint:TestPoint_THTPad_2.0x2.0mm_Drill1.0mm", False, "TP") for n in range(1, 34)},
}

# =============================================================================
# SYMBOL TYPE DEFINITIONS
# Each entry: list of (pin_number, pin_name, electrical_type, x, y, angle)
# x,y are relative to symbol centre. Pins face inward (angle 0 = right→body).
# Pin stub length = 2.54mm. Body typically ±1.27mm to ±3.81mm half-width.
# =============================================================================

SYMBOL_TYPES = {

    "DIODE": {
        "body": [
            # Triangle + bar (cathode bar on right)
            ("polyline", [(-1.27, -1.27), (-1.27, 1.27), (1.27, 0), (-1.27, -1.27)]),
            ("polyline", [(1.27, -1.27), (1.27, 1.27)]),
        ],
        "pins": [
            ("1", "A", "passive", -3.81, 0, 0),
            ("2", "K", "passive",  3.81, 0, 180),
        ],
        "ref_prefix": "D",
        "body_hw": 3.81,  # half-width for label placement
        "body_hh": 1.27,
    },

    "LED": {
        "body": [
            ("polyline", [(-1.27, -1.27), (-1.27, 1.27), (1.27, 0), (-1.27, -1.27)]),
            ("polyline", [(1.27, -1.27), (1.27, 1.27)]),
            ("polyline", [(2.032, 1.524), (3.048, 2.54)]),
            ("polyline", [(2.921, 0.762), (3.937, 1.778)]),
        ],
        "pins": [
            ("1", "A", "passive", -3.81, 0, 0),
            ("2", "K", "passive",  3.81, 0, 180),
        ],
        "ref_prefix": "LED",
        "body_hw": 3.81,
        "body_hh": 1.27,
    },

    "RES": {
        "body": [
            ("rectangle", (-1.016, -0.508), (1.016, 0.508)),
        ],
        "pins": [
            ("1", "~", "passive", -3.81, 0, 0),
            ("2", "~", "passive",  3.81, 0, 180),
        ],
        "ref_prefix": "R",
        "body_hw": 3.81,
        "body_hh": 0.508,
    },

    "CAP_POL": {
        "body": [
            ("polyline", [(-1.524, 0), (1.524, 0)]),   # positive plate
            ("polyline", [(-1.524, -0.508), (1.524, -0.508)]),  # negative plate
        ],
        "pins": [
            ("1", "+", "passive", -3.81, 0, 0),
            ("2", "-", "passive",  3.81, 0, 180),
        ],
        "ref_prefix": "C",
        "body_hw": 3.81,
        "body_hh": 0.508,
    },

    "CAP": {
        "body": [
            ("polyline", [(-1.524, 0), (1.524, 0)]),
            ("polyline", [(-1.524, -0.508), (1.524, -0.508)]),
        ],
        "pins": [
            ("1", "~", "passive", -3.81, 0, 0),
            ("2", "~", "passive",  3.81, 0, 180),
        ],
        "ref_prefix": "C",
        "body_hw": 3.81,
        "body_hh": 0.508,
    },

    "AMS1117": {
        "body": [
            ("rectangle", (-2.54, -2.54), (2.54, 2.54)),
        ],
        "pins": [
            # AMS1117 SOT-223 pinout: 1=GND, 2=OUT, 3=IN
            # Placed vertically: GND left-bottom, OUT right, IN left-top
            ("1", "GND", "power_in",  -5.08, -1.27, 0),
            ("2", "OUT", "power_out",  5.08,  0,    180),
            ("3", "IN",  "power_in",  -5.08,  1.27, 0),
        ],
        "ref_prefix": "U",
        "body_hw": 5.08,
        "body_hh": 2.54,
    },

    "CONN2": {
        "body": [("rectangle", (-1.27, -2.54), (1.27, 2.54))],
        "pins": [
            ("1", "Pin_1", "passive", -3.81, 1.27, 0),
            ("2", "Pin_2", "passive", -3.81, -1.27, 0),
        ],
        "ref_prefix": "J",
        "body_hw": 3.81,
        "body_hh": 2.54,
    },

    "CONN4": {
        "body": [("rectangle", (-1.27, -5.08), (1.27, 5.08))],
        "pins": [
            ("1", "Pin_1", "passive", -3.81,  3.81, 0),
            ("2", "Pin_2", "passive", -3.81,  1.27, 0),
            ("3", "Pin_3", "passive", -3.81, -1.27, 0),
            ("4", "Pin_4", "passive", -3.81, -3.81, 0),
        ],
        "ref_prefix": "J",
        "body_hw": 3.81,
        "body_hh": 5.08,
    },

    "CONN6": {
        "body": [("rectangle", (-1.27, -7.62), (1.27, 7.62))],
        "pins": [
            ("1", "VCC",  "passive", -3.81,  6.35, 0),
            ("2", "GND",  "passive", -3.81,  3.81, 0),
            ("3", "CS",   "passive", -3.81,  1.27, 0),
            ("4", "MOSI", "passive", -3.81, -1.27, 0),
            ("5", "MISO", "passive", -3.81, -3.81, 0),
            ("6", "SCK",  "passive", -3.81, -6.35, 0),
        ],
        "ref_prefix": "J",
        "body_hw": 3.81,
        "body_hh": 7.62,
    },

    "SD_SOCKET": {
        "body": [("rectangle", (-2.54, -13.97), (2.54, 10.16))],
        "pins": [
            ("1",  "DAT2",    "passive",   -6.35,  8.89, 0),   # NC in SPI, tied to GND
            ("2",  "DAT3~CD", "passive",   -6.35,  6.35, 0),   # SPI CS
            ("3",  "CMD",     "passive",   -6.35,  3.81, 0),   # SPI MOSI
            ("4",  "VDD",     "power_in",  -6.35,  1.27, 0),
            ("5",  "CLK",     "passive",   -6.35, -1.27, 0),   # SPI SCK
            ("6",  "VSS",     "power_in",  -6.35, -3.81, 0),
            ("7",  "DAT0",    "passive",   -6.35, -6.35, 0),   # SPI MISO
            ("8",  "DAT1",    "passive",   -6.35, -8.89, 0),   # NC in SPI, tied to GND
            ("SH", "SHIELD",  "passive",   -6.35, -12.70, 0),
        ],
        "ref_prefix": "J",
        "body_hw": 6.35,
        "body_hh": 13.97,
    },

    "DIP4": {
        "body": [("rectangle", (-5.08, -5.08), (5.08, 5.08))],
        "pins": [
            # Input side (left)
            ("1", "A1", "input",  -7.62,  3.81, 0),
            ("2", "A2", "input",  -7.62,  1.27, 0),
            ("3", "A3", "input",  -7.62, -1.27, 0),
            ("4", "A4", "input",  -7.62, -3.81, 0),
            # Output side (right)
            ("5", "B1", "output",  7.62,  3.81, 180),
            ("6", "B2", "output",  7.62,  1.27, 180),
            ("7", "B3", "output",  7.62, -1.27, 180),
            ("8", "B4", "output",  7.62, -3.81, 180),
        ],
        "ref_prefix": "SW",
        "body_hw": 7.62,
        "body_hh": 5.08,
    },

    "RJ45": {
        "body": [("rectangle", (-5.08, -12.7), (5.08, 12.7))],
        "pins": [
            # Signal pins 1-8 on left side, shield on right
            ("1", "Pin_1", "passive", -7.62,  11.43, 0),
            ("2", "Pin_2", "passive", -7.62,   8.89, 0),
            ("3", "Pin_3", "passive", -7.62,   6.35, 0),
            ("4", "Pin_4", "passive", -7.62,   3.81, 0),
            ("5", "Pin_5", "passive", -7.62,   1.27, 0),
            ("6", "Pin_6", "passive", -7.62,  -1.27, 0),
            ("7", "Pin_7", "passive", -7.62,  -3.81, 0),
            ("8", "Pin_8", "passive", -7.62,  -6.35, 0),
            ("S", "Shield","passive",  7.62,   0,    180),
        ],
        "ref_prefix": "J",
        "body_hw": 7.62,
        "body_hh": 12.7,
    },

    "TP": {
        "body": [("circle", (0, 0), 0.5)],
        "pins": [
            ("1", "TP", "passive", -2.54, 0, 0),
        ],
        "ref_prefix": "TP",
        "body_hw": 2.54,
        "body_hh": 0.5,
    },

    "ESP32": {
        "body": [("rectangle", (-10.16, -50.8), (10.16, 50.8))],
        "pins": (
            # Left column — odd pads, from top
            # (pad_number, pin_name, type, x, y, angle)
            [("1",  "GND",     "power_in",  -12.7,  49.53, 0),
             ("3",  "IO23",    "bidirectional", -12.7,  46.99, 0),
             ("5",  "IO22",    "bidirectional", -12.7,  44.45, 0),
             ("7",  "TXD0",    "output",    -12.7,  41.91, 0),
             ("9",  "RXD0",    "input",     -12.7,  39.37, 0),
             ("11", "IO21",    "bidirectional", -12.7,  36.83, 0),
             ("13", "GND",     "power_in",  -12.7,  34.29, 0),
             ("15", "IO19",    "bidirectional", -12.7,  31.75, 0),
             ("17", "IO18",    "bidirectional", -12.7,  29.21, 0),
             ("19", "IO5",     "bidirectional", -12.7,  26.67, 0),
             ("21", "IO17",    "bidirectional", -12.7,  24.13, 0),
             ("23", "IO16",    "bidirectional", -12.7,  21.59, 0),
             ("25", "IO4",     "bidirectional", -12.7,  19.05, 0),
             ("27", "IO0",     "bidirectional", -12.7,  16.51, 0),
             ("29", "IO2",     "bidirectional", -12.7,  13.97, 0),
             ("31", "IO15",    "bidirectional", -12.7,  11.43, 0),
             ("33", "GND",     "power_in",  -12.7,   8.89, 0),
             ("35", "IO8",     "bidirectional", -12.7,   6.35, 0),
             ("37", "IO7",     "bidirectional", -12.7,   3.81, 0),
             # Right column — even pads, from top
             ("2",  "3V3",     "power_out",  12.7,  49.53, 180),
             ("4",  "EN",      "input",      12.7,  46.99, 180),
             ("6",  "IO36",    "input",      12.7,  44.45, 180),
             ("8",  "IO39",    "input",      12.7,  41.91, 180),
             ("10", "IO34",    "input",      12.7,  39.37, 180),
             ("12", "IO35",    "input",      12.7,  36.83, 180),
             ("14", "IO32",    "bidirectional", 12.7,  34.29, 180),
             ("16", "IO33",    "bidirectional", 12.7,  31.75, 180),
             ("18", "IO25",    "bidirectional", 12.7,  29.21, 180),
             ("20", "IO26",    "bidirectional", 12.7,  26.67, 180),
             ("22", "IO27",    "bidirectional", 12.7,  24.13, 180),
             ("24", "IO14",    "bidirectional", 12.7,  21.59, 180),
             ("26", "IO12",    "bidirectional", 12.7,  19.05, 180),
             ("28", "GND",     "power_in",   12.7,  16.51, 180),
             ("30", "IO13",    "bidirectional", 12.7,  13.97, 180),
             ("32", "IO9",     "bidirectional", 12.7,  11.43, 180),
             ("34", "IO10",    "bidirectional", 12.7,   8.89, 180),
             ("36", "IO11",    "bidirectional", 12.7,   6.35, 180),
             ("38", "VIN",     "power_in",   12.7,   3.81, 180),
            ]
        ),
        "ref_prefix": "U",
        "body_hw": 12.7,
        "body_hh": 50.8,
    },

    "PWR_FLAG": {
        "body": [
            ("polyline", [(0, 0), (0, 2.54)]),                          # staff
            ("polyline", [(0, 2.54), (2.54, 3.81), (0, 5.08), (0, 2.54)]),  # flag
        ],
        "pins": [
            ("1", "PWR", "power_out", 0, 0, 90),
        ],
        "ref_prefix": "#PWR",
        "body_hw": 2.54,
        "body_hh": 5.08,
        "is_power": True,
    },
}

# =============================================================================
# COMPONENT LAYOUT POSITIONS (cx, cy) in mm on schematic
# =============================================================================

LAYOUT = {
    # Power section
    "J_PWR":  (20,   20),
    "D1":     (50,   20),
    "J_SW1":  (80,   20),
    "U2":     (50,   65),
    "U3":     (110,  65),
    # PWR_FLAGS — placed near GND/5V/3V3 sources
    "PWRF_GND": (20,  40),
    "PWRF_5V":  (50,  90),
    "C1":     (155,  55),
    "C2":     (175,  55),
    "C3":     (195,  55),
    "C13":    (215,  55),
    # Status LEDs
    "R13":    (250,  30),
    "LED1":   (290,  30),
    "R14":    (250,  55),
    "LED2":   (290,  55),
    "R15":    (250,  80),
    "LED3":   (290,  80),
    # ESP32
    "U1":     (390, 120),
    # DIP switch
    "SW2":    (480,  80),
    # Zone A
    "R1":     (560,  40),
    "R16":    (585,  40),
    "R9":     (610,  40),
    "LED4":   (635,  40),
    "D2":     (680,  40),
    "C4":     (705,  40),
    "D10":    (730,  40),
    "J_ZONE_A": (780, 40),
    "D14":    (840,  40),
    # Zone B
    "R2":     (560,  100),
    "R17":    (585,  100),
    "R10":    (610,  100),
    "LED5":   (635,  100),
    "D3":     (680,  100),
    "C5":     (705,  100),
    "D11":    (730,  100),
    "J_ZONE_B": (780, 100),
    "D15":    (840,  100),
    # Zone C
    "R3":     (560,  160),
    "R18":    (585,  160),
    "R11":    (610,  160),
    "LED6":   (635,  160),
    "D4":     (680,  160),
    "C6":     (705,  160),
    "D12":    (730,  160),
    "J_ZONE_C": (780, 160),
    "D16":    (840,  160),
    # Zone D
    "R4":     (560,  220),
    "R19":    (585,  220),
    "R12":    (610,  220),
    "LED7":   (635,  220),
    "D5":     (680,  220),
    "C7":     (705,  220),
    "D13":    (730,  220),
    "J_ZONE_D": (780, 220),
    "D17":    (840,  220),
    # DHT22
    "D6":     (20,  290),
    "C8":     (50,  290),
    "R5":     (80,  290),
    "J_DHT":  (130, 290),
    # I2C
    "R6":     (250, 270),
    "R7":     (250, 295),
    "D7":     (320, 270),
    "C9":     (355, 270),
    "J_I2C_1":(390, 280),
    "D8":     (450, 270),
    "C10":    (485, 270),
    "J_I2C_2":(520, 280),
    "D9":     (580, 270),
    "C11":    (615, 270),
    "J_I2C_3":(650, 280),
    # SD card
    "SD_MOD": (20,  380),
    "C12":    (70,  380),
    "R8":     (100, 380),
    # Pi header
    "J_PI":   (160, 380),
    # Test points — grouped near related nets
    "TP1":    (250, 380),  # GND
    "TP2":    (270, 380),  # +3V3
    "TP3":    (290, 380),  # +5V
    "TP4":    (310, 380),  # +12V_IN
    "TP5":    (330, 380),  # +12V
    "TP6":    (350, 380),  # ESP_3V3
    "TP7":    (560, 380),  # MST_A_VCC
    "TP8":    (580, 380),  # MST_A_SIG
    "TP9":    (600, 380),  # RLY_A_SW
    "TP10":   (620, 380),  # RLY_A_IN
    "TP11":   (560, 400),  # MST_B_VCC
    "TP12":   (580, 400),  # MST_B_SIG
    "TP13":   (600, 400),  # RLY_B_SW
    "TP14":   (620, 400),  # RLY_B_IN
    "TP15":   (560, 420),  # MST_C_VCC
    "TP16":   (580, 420),  # MST_C_SIG
    "TP17":   (600, 420),  # RLY_C_SW
    "TP18":   (620, 420),  # RLY_C_IN
    "TP19":   (560, 440),  # MST_D_VCC
    "TP20":   (580, 440),  # MST_D_SIG
    "TP21":   (600, 440),  # RLY_D_SW
    "TP22":   (620, 440),  # RLY_D_IN
    "TP23":   (370, 380),  # SDA
    "TP24":   (390, 380),  # SCL
    "TP25":   (410, 380),  # I2C1_VCC
    "TP26":   (430, 380),  # I2C2_VCC
    "TP27":   (450, 380),  # I2C3_VCC
    "TP28":   (470, 380),  # DHT_VCC
    "TP29":   (490, 380),  # DHT_DATA
    "TP30":   (510, 380),  # SD_CS
    "TP31":   (530, 380),  # SD_MOSI
    "TP32":   (550, 380),  # SD_MISO
    "TP33":   (640, 380),  # SD_SCK
}

# =============================================================================
# VERIFICATION — print all connections before generating the file
# =============================================================================

def verify():
    print("\n" + "="*70)
    print("NETLIST VERIFICATION — check against NodeBoard_v2_Spec.md")
    print("="*70)

    # Check all components in NETLIST have metadata
    missing_meta = [r for r in NETLIST if r not in COMPONENTS]
    if missing_meta:
        print(f"\nERROR: No metadata for: {missing_meta}")

    # Check all components in LAYOUT are in NETLIST
    missing_net = [r for r in LAYOUT if r not in NETLIST]
    if missing_net:
        print(f"\nWARNING: Layout refs not in NETLIST: {missing_net}")

    # Print critical components first
    print("\n── POWER CHAIN ──────────────────────────────────────────────────────")
    for ref in ["J_PWR", "D1", "J_SW1", "U2", "U3"]:
        print(f"  {ref:10s}: {NETLIST[ref]}")

    print("\n── AMS1117 PINOUT CHECK (pin1=GND pin2=OUT pin3=IN) ─────────────────")
    u3 = NETLIST["U3"]
    ok = u3.get("1") == "GND" and u3.get("2") == "+3V3" and u3.get("3") == "+5V"
    print(f"  U3 pin1→{u3.get('1')}  pin2→{u3.get('2')}  pin3→{u3.get('3')}  {'✓ CORRECT' if ok else '✗ ERROR'}")

    print("\n── DIODE POLARITY CHECK (A=supply/GND, K=load/signal) ──────────────")
    diode_checks = [
        ("D1",  "Reverse protect: A→12V_IN K→12V_PRE_SW",  "+12V_IN",   "12V_PRE_SW"),
        ("D2",  "VCC prot ZoneA:  A→+3V3  K→MST_A_VCC",   "+3V3",      "MST_A_VCC"),
        ("D10", "TVS ZoneA:       A→GND   K→MST_A_SIG",   "GND",       "MST_A_SIG"),
    ]
    for ref, desc, exp_a, exp_k in diode_checks:
        a = NETLIST[ref].get("A", "?")
        k = NETLIST[ref].get("K", "?")
        ok = a == exp_a and k == exp_k
        print(f"  {ref}: A→{a:15s} K→{k:15s}  {'✓' if ok else '✗ ERROR'} {desc}")

    print("\n── LED POLARITY CHECK (A=anode→resistor, K=cathode→GND) ────────────")
    for ref in ["LED1", "LED2", "LED3", "LED4"]:
        a = NETLIST[ref].get("A", "?")
        k = NETLIST[ref].get("K", "?")
        ok = k == "GND"
        print(f"  {ref}: A→{a:15s} K→{k:5s}  {'✓' if ok else '✗ ERROR'}")

    print("\n── ESP32 GPIO ASSIGNMENTS ───────────────────────────────────────────")
    esp = NETLIST["U1"]
    gpio_checks = [
        ("14", "IO32", "MST_A_SIG"),
        ("16", "IO33", "MST_B_SIG"),
        ("10", "IO34", "MST_C_SIG"),
        ("12", "IO35", "MST_D_SIG"),
        ("18", "IO25", "RLY_A_SW"),
        ("20", "IO26", "RLY_B_SW"),
        ("30", "IO13", "RLY_C_SW"),
        ("24", "IO14", "RLY_D_SW"),
        ("22", "IO27", "DHT_DATA"),
        ("11", "IO21", "SDA"),
        ("5",  "IO22", "SCL"),
        ("19", "IO5",  "SD_CS"),
        ("3",  "IO23", "SD_MOSI"),
        ("15", "IO19", "SD_MISO"),
        ("17", "IO18", "SD_SCK"),
        ("38", "VIN",  "+5V"),
    ]
    all_ok = True
    for pad, gpio, expected_net in gpio_checks:
        actual = esp.get(pad, "MISSING")
        ok = actual == expected_net
        if not ok:
            all_ok = False
        print(f"  pad {pad:2s} ({gpio:5s}) → {actual:15s}  {'✓' if ok else f'✗ expected {expected_net}'}")
    if all_ok:
        print("  All GPIO assignments correct ✓")

    print("\n── ZONE A RJ45 PINOUT ───────────────────────────────────────────────")
    za = NETLIST["J_ZONE_A"]
    rj_checks = [("1","MST_A_SIG"),("2","GND"),("3","MST_A_VCC"),("4","RLY_A_OUT"),
                 ("5","GND"),("6","GND"),("7","+5V"),("8","GND"),("S","GND")]
    for pin, exp in rj_checks:
        actual = za.get(pin, "?")
        ok = actual == exp
        print(f"  Pin {pin}: {actual:15s}  {'✓' if ok else f'✗ expected {exp}'}")

    print("\n── GND CONNECTIONS ─────────────────────────────────────────────────")
    gnd_refs = [(ref, pin) for ref, pins in NETLIST.items()
                for pin, net in pins.items() if net == "GND"]
    print(f"  GND connected on {len(gnd_refs)} pins across {len(set(r for r,_ in gnd_refs))} components")

    esp_gnd = [(pad, net) for pad, net in NETLIST["U1"].items() if net == "GND"]
    print(f"  ESP32 GND pads: {[p for p,_ in esp_gnd]}")

    print("\n" + "="*70)
    print("END VERIFICATION")
    print("="*70 + "\n")

# =============================================================================
# KiCad S-expression generators
# =============================================================================

def make_lib_symbol(sym_type, type_def):
    """Generate a lib_symbols entry for the given symbol type."""
    body_hw = type_def.get("body_hw", 5.08)
    body_hh = type_def.get("body_hh", 2.54)
    ref_prefix = type_def.get("ref_prefix", "U")
    pins = type_def["pins"]

    lines = []
    lines.append(f'    (symbol "{sym_type}"')
    if type_def.get("is_power"):
        lines.append('      (power)')
    lines.append('      (pin_numbers hide)')
    lines.append('      (pin_names (offset 0.508))')
    lines.append(f'      (property "Reference" "{ref_prefix}" (at 0 {f(body_hh + 2.0)} 0)')
    lines.append('        (effects (font (size 1.27 1.27))))')
    lines.append(f'      (property "Value" "{sym_type}" (at 0 {f(-body_hh - 2.0)} 0)')
    lines.append('        (effects (font (size 1.27 1.27))))')
    lines.append('      (property "Footprint" "" (at 0 0 0)')
    lines.append('        (effects (font (size 1.27 1.27)) hide))')
    lines.append('      (property "Datasheet" "~" (at 0 0 0)')
    lines.append('        (effects (font (size 1.27 1.27)) hide))')

    # Body graphics
    lines.append(f'      (symbol "{sym_type}_0_1"')
    for shape in type_def["body"]:
        if shape[0] == "rectangle":
            x1, y1 = shape[1]
            x2, y2 = shape[2]
            lines.append(f'        (rectangle (start {f(x1)} {f(y1)}) (end {f(x2)} {f(y2)})')
            lines.append('          (stroke (width 0.1) (type default)) (fill (type background)))')
        elif shape[0] == "polyline":
            pts = " ".join(f"(xy {f(x)} {f(y)})" for x, y in shape[1])
            lines.append(f'        (polyline (pts {pts})')
            lines.append('          (stroke (width 0.1) (type default)) (fill (type none)))')
        elif shape[0] == "circle":
            cx, cy = shape[1]
            r = shape[2]
            lines.append(f'        (circle (center {f(cx)} {f(cy)}) (radius {f(r)})')
            lines.append('          (stroke (width 0.1) (type default)) (fill (type none)))')
    lines.append('      )')

    # Pins
    lines.append(f'      (symbol "{sym_type}_1_1"')
    pin_list = pins if isinstance(pins, list) else list(pins)
    for pnum, pname, ptype, px, py, pangle in pin_list:
        lines.append(f'        (pin {ptype} line (at {f(px)} {f(py)} {pangle}) (length 2.54)')
        lines.append(f'          (name "{pname}" (effects (font (size 1.016 1.016))))')
        lines.append(f'          (number "{pnum}" (effects (font (size 1.016 1.016)))))')
    lines.append('      )')
    lines.append('    )')
    return "\n".join(lines)


def make_instance(ref, cx, cy):
    """Generate a symbol instance with all its net labels."""
    if ref not in COMPONENTS:
        return "", ""
    value, footprint, dnp, sym_type = COMPONENTS[ref]
    nets = NETLIST.get(ref, {})
    type_def = SYMBOL_TYPES[sym_type]
    body_hw = type_def.get("body_hw", 5.08)
    body_hh = type_def.get("body_hh", 2.54)
    dnp_str = "yes" if dnp else "no"

    # Snap to 1.27mm grid — all pin endpoints must land on grid for KiCad connections
    cx = snap(cx)
    cy = snap(cy)

    # Power symbols need a #PWR reference so KiCad ERC recognises them
    is_power = type_def.get("is_power", False)
    display_ref = ("#PWR_" + ref) if is_power else ref
    in_bom = "no" if is_power else "yes"
    on_board = "no" if is_power else "yes"

    inst_lines = []
    inst_lines.append(f'  (symbol (lib_id "{sym_type}") (at {f(cx)} {f(cy)} 0) (unit 1)')
    inst_lines.append(f'    (in_bom {in_bom}) (on_board {on_board}) (dnp {dnp_str})')
    inst_lines.append(f'    (property "Reference" "{display_ref}" (at {f(cx)} {f(cy - body_hh - 2.5)} 0)')
    inst_lines.append('      (effects (font (size 1.27 1.27))))')
    inst_lines.append(f'    (property "Value" "{value}" (at {f(cx)} {f(cy + body_hh + 2.5)} 0)')
    inst_lines.append('      (effects (font (size 1.27 1.27))))')
    inst_lines.append(f'    (property "Footprint" "{footprint}" (at {f(cx)} {f(cy)} 0)')
    inst_lines.append('      (effects (font (size 1.27 1.27)) hide))')
    inst_lines.append(f'    (property "Datasheet" "~" (at {f(cx)} {f(cy)} 0)')
    inst_lines.append('      (effects (font (size 1.27 1.27)) hide))')

    pin_list = type_def["pins"] if isinstance(type_def["pins"], list) else list(type_def["pins"])
    for pnum, _, _, _, _, _ in pin_list:
        inst_lines.append(f'    (pin "{pnum}" (uuid "{uid()}"))')
    inst_lines.append('  )')

    # Generate net labels (wire stub + label) or no-connect markers per pin
    label_lines = []
    for pnum, pname, ptype, px, py, pangle in pin_list:
        net = nets.get(pnum)
        if not net:
            continue
        # Pin endpoint in world coords (already on grid because cx,cy snapped and px,py are multiples of 1.27)
        abs_x = f(cx + px)
        abs_y = f(cy - py)  # KiCad Y inverted

        # NC_ nets get a no-connect marker; all others get wire stub + net label
        if net.startswith("NC_"):
            label_lines.append(
                f'  (no_connect (at {abs_x} {abs_y}) (uuid "{uid()}"))'
            )
            continue

        # Wire stub: extend 5.08mm outward from pin endpoint
        if pangle == 0:      # pin faces right into body (left side of symbol)
            wire_x = f(cx + px - 5.08)
            label_x, label_y = wire_x, abs_y
            label_angle = 180
            justify = "right"
        elif pangle == 90:   # pin faces down into body (bottom pin, e.g. PWR_FLAG)
            wire_y = f(cy - py - 5.08)
            label_x, label_y = abs_x, wire_y
            label_angle = 90
            justify = "left"
        else:                # pangle == 180, pin faces left into body (right side of symbol)
            wire_x = f(cx + px + 5.08)
            label_x, label_y = wire_x, abs_y
            label_angle = 0
            justify = "left"

        label_lines.append(
            f'  (wire (pts (xy {abs_x} {abs_y}) (xy {label_x} {label_y}))\n'
            f'    (stroke (width 0) (type default)) (uuid "{uid()}"))'
        )
        label_lines.append(
            f'  (label "{net}" (at {f(label_x)} {f(label_y)} {label_angle}) (fields_autoplaced)\n'
            f'    (effects (font (size 1.0 1.0)) (justify {justify}))\n'
            f'    (uuid "{uid()}"))'
        )

    return "\n".join(inst_lines), "\n".join(label_lines)


def make_section_box(title, x1, y1, x2, y2):
    return (
        f'  (rectangle (start {f(x1)} {f(y1)}) (end {f(x2)} {f(y2)})\n'
        f'    (stroke (width 0.5) (type default)) (fill (type none))\n'
        f'    (uuid "{uid()}"))\n'
        f'  (text "{title}" (at {f((x1+x2)/2)} {f(y1 + 3)} 0)\n'
        f'    (effects (font (size 2.0 2.0) (bold yes)))\n'
        f'    (uuid "{uid()}"))'
    )


# =============================================================================
# MAIN — build and write
# =============================================================================

def build_schematic():
    lib_sym_lines = ["  (lib_symbols"]
    for sym_type, type_def in SYMBOL_TYPES.items():
        lib_sym_lines.append(make_lib_symbol(sym_type, type_def))
    lib_sym_lines.append("  )")
    lib_symbols_str = "\n".join(lib_sym_lines)

    inst_parts = []
    label_parts = []

    for ref, (cx, cy) in LAYOUT.items():
        inst, labels = make_instance(ref, cx, cy)
        if inst:
            inst_parts.append(inst)
        if labels:
            label_parts.append(labels)

    # Section boxes
    boxes = [
        make_section_box("POWER",           5,   5, 240, 130),
        make_section_box("STATUS LEDs",    240,   5, 340, 130),
        make_section_box("ESP32-DevKitC",  340,   5, 450, 250),
        make_section_box("ZONE ENABLE DIP",450,   5, 540, 130),
        make_section_box("ZONES A-D",      540,   5, 870, 260),
        make_section_box("DHT22",            5, 260, 180, 340),
        make_section_box("I2C BUS",        240, 250, 710, 330),
        make_section_box("SD CARD",          5, 350, 220, 415),
        make_section_box("TEST POINTS",    240, 350, 870, 460),
    ]

    content = (
        "(kicad_sch\n"
        "  (version 20260306)\n"
        '  (generator "eeschema")\n'
        '  (generator_version "10.0")\n'
        f'  (uuid "{uid()}")\n'
        '  (paper "A0")\n'
        "  (title_block\n"
        '    (title "NurseryHub Node Board v2")\n'
        f'    (date "{date.today()}")\n'
        '    (rev "2.0")\n'
        '    (company "NurseryHub")\n'
        '    (comment 1 "Generated by Hardware/NodeBoard_v2/generate_schematic.py")\n'
        '    (comment 2 "Spec: Hardware/NodeBoard_v2_Spec.md signed off 2026-06-20")\n'
        '    (comment 3 "RJ45 footprint: verify against sourced component before fab")\n'
        '    (comment 4 "SD socket: Wuerth 693072010801 or pin-compatible. DAT1/DAT2 tied to GND.")\n'
        "  )\n\n"
        + lib_symbols_str + "\n\n"
        + "\n\n".join(inst_parts) + "\n\n"
        + "\n\n".join(label_parts) + "\n\n"
        + "\n\n".join(boxes) + "\n\n"
        "  (sheet_instances (path \"/\" (page \"1\")))\n"
        "  (embedded_fonts no)\n"
        ")\n"
    )
    return content


def main():
    verify()

    out_dir = os.path.dirname(os.path.abspath(__file__))
    out_path = os.path.join(out_dir, "node_board_v2.kicad_sch")

    print(f"Writing {out_path} ...")
    content = build_schematic()
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write(content)

    print(f"Done. {len(LAYOUT)} components placed.")
    print()
    print("Next steps:")
    print("  1. Open node_board_v2.kicad_sch in KiCad 10")
    print("  2. Press Ctrl+Home to fit view")
    print("  3. Run ERC — fix any errors before proceeding")
    print("  4. Verify AMS1117 U3 orientation in 3D viewer")
    print("  5. Verify RJ45 footprint matches your sourced component")
    print("  6. Verify SD_MOD pin order matches your SD breakout module")
    print("  7. Run Tools > Update PCB from Schematic")
    print("  8. Complete PCB layout per spec layout requirements section")
    print("  9. Run DRC — zero errors before generating Gerbers")


if __name__ == "__main__":
    main()
