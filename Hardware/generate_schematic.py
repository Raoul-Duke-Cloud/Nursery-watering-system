#!/usr/bin/env python3
"""
NurseryHub Node Board — KiCad Netlist Generator

Generates a KiCad-compatible netlist XML (.net) from the board design.
Import into KiCad PCB editor via: File > Import Netlist

Usage:
    python generate_schematic.py
    # outputs: node_board.net

Then in KiCad:
    1. Open KiCad PCB editor (pcbnew)
    2. File > Import Netlist > select node_board.net
    3. Assign footprints for any unresolved refs
    4. Place and route

No dependencies beyond Python 3 standard library.
"""

import xml.etree.ElementTree as ET
from xml.dom import minidom
from datetime import date

# ── Components ────────────────────────────────────────────────────────────────

COMPONENTS = [
    # ref, value, footprint, description
    ("U1",  "ESP32-DevKitC-32E",   "Connector_PinHeader_2.54mm:PinHeader_2x19_P2.54mm_Vertical",         "ESP32 DevKitC — socketed on 2x19 female headers"),
    ("U2",  "LM2596-5V_Module",    "Connector_PinHeader_2.54mm:PinHeader_1x04_P2.54mm_Vertical",         "Buck converter module 12V→5V — socketed"),
    ("U3",  "AMS1117-3.3",         "Package_TO_SOT_SMD:SOT-223-3_TabPin2",                               "3.3V LDO — LCSC C6186"),

    ("D1",  "SS14",  "Diode_SMD:D_SMA",  "12V input reverse polarity protection"),
    ("D2",  "SS14",  "Diode_SMD:D_SMA",  "MST-A VCC reverse polarity protection"),
    ("D3",  "SS14",  "Diode_SMD:D_SMA",  "MST-B VCC reverse polarity protection"),
    ("D4",  "SS14",  "Diode_SMD:D_SMA",  "MST-C VCC reverse polarity protection"),
    ("D5",  "SS14",  "Diode_SMD:D_SMA",  "MST-D VCC reverse polarity protection"),
    ("D6",  "SS14",  "Diode_SMD:D_SMA",  "DHT22 VCC reverse polarity protection"),
    ("D7",  "SS14",  "Diode_SMD:D_SMA",  "I2C-1 VCC reverse polarity protection"),
    ("D8",  "SS14",  "Diode_SMD:D_SMA",  "I2C-2 VCC reverse polarity protection"),
    ("D9",  "SS14",  "Diode_SMD:D_SMA",  "I2C-3 VCC reverse polarity protection"),
    ("D10", "SMBJ3.3A", "Diode_SMD:D_SMB", "MST-A SIG TVS clamp"),
    ("D11", "SMBJ3.3A", "Diode_SMD:D_SMB", "MST-B SIG TVS clamp"),
    ("D12", "SMBJ3.3A", "Diode_SMD:D_SMB", "MST-C SIG TVS clamp"),
    ("D13", "SMBJ3.3A", "Diode_SMD:D_SMB", "MST-D SIG TVS clamp"),
    ("D14", "SS14",  "Diode_SMD:D_SMA",  "Relay A coil flyback — DNP if using relay modules"),
    ("D15", "SS14",  "Diode_SMD:D_SMA",  "Relay B coil flyback — DNP"),
    ("D16", "SS14",  "Diode_SMD:D_SMA",  "Relay C coil flyback — DNP"),
    ("D17", "SS14",  "Diode_SMD:D_SMA",  "Relay D coil flyback — DNP"),

    ("R1",  "1k",  "Resistor_SMD:R_0402_1005Metric", "Relay A IN series resistor"),
    ("R2",  "1k",  "Resistor_SMD:R_0402_1005Metric", "Relay B IN series resistor"),
    ("R3",  "1k",  "Resistor_SMD:R_0402_1005Metric", "Relay C IN series resistor"),
    ("R4",  "1k",  "Resistor_SMD:R_0402_1005Metric", "Relay D IN series resistor"),
    ("R5",  "10k", "Resistor_SMD:R_0402_1005Metric", "DHT22 DATA pull-up"),
    ("R6",  "4.7k","Resistor_SMD:R_0402_1005Metric", "I2C SDA pull-up"),
    ("R7",  "4.7k","Resistor_SMD:R_0402_1005Metric", "I2C SCL pull-up"),
    ("R8",  "10k", "Resistor_SMD:R_0402_1005Metric", "SD CS pull-up"),
    ("R9",  "1k",  "Resistor_SMD:R_0402_1005Metric", "Zone A LED current limit"),
    ("R10", "1k",  "Resistor_SMD:R_0402_1005Metric", "Zone B LED current limit"),
    ("R11", "1k",  "Resistor_SMD:R_0402_1005Metric", "Zone C LED current limit"),
    ("R12", "1k",  "Resistor_SMD:R_0402_1005Metric", "Zone D LED current limit"),
    ("R13", "1k",  "Resistor_SMD:R_0402_1005Metric", "LED1 (12V) current limit"),
    ("R14", "1k",  "Resistor_SMD:R_0402_1005Metric", "LED2 (5V) current limit"),
    ("R15", "1k",  "Resistor_SMD:R_0402_1005Metric", "LED3 (3V3) current limit"),
    ("R16", "10k", "Resistor_SMD:R_0402_1005Metric", "Zone A IN pull-down"),
    ("R17", "10k", "Resistor_SMD:R_0402_1005Metric", "Zone B IN pull-down"),
    ("R18", "10k", "Resistor_SMD:R_0402_1005Metric", "Zone C IN pull-down"),
    ("R19", "10k", "Resistor_SMD:R_0402_1005Metric", "Zone D IN pull-down"),

    ("C1",  "100uF_25V", "Capacitor_SMD:C_Elec_6.3x7.7",           "12V bulk decoupling"),
    ("C2",  "100uF_25V", "Capacitor_SMD:C_Elec_6.3x7.7",           "5V bulk decoupling"),
    ("C3",  "100uF_25V", "Capacitor_SMD:C_Elec_6.3x7.7",           "3V3 bulk decoupling"),
    ("C4",  "100nF",     "Capacitor_SMD:C_0402_1005Metric",         "MST-A VCC decoupling"),
    ("C5",  "100nF",     "Capacitor_SMD:C_0402_1005Metric",         "MST-B VCC decoupling"),
    ("C6",  "100nF",     "Capacitor_SMD:C_0402_1005Metric",         "MST-C VCC decoupling"),
    ("C7",  "100nF",     "Capacitor_SMD:C_0402_1005Metric",         "MST-D VCC decoupling"),
    ("C8",  "100nF",     "Capacitor_SMD:C_0402_1005Metric",         "DHT22 VCC decoupling"),
    ("C9",  "100nF",     "Capacitor_SMD:C_0402_1005Metric",         "I2C-1 VCC decoupling"),
    ("C10", "100nF",     "Capacitor_SMD:C_0402_1005Metric",         "I2C-2 VCC decoupling"),
    ("C11", "100nF",     "Capacitor_SMD:C_0402_1005Metric",         "I2C-3 VCC decoupling"),
    ("C12", "100nF",     "Capacitor_SMD:C_0402_1005Metric",         "SD VCC decoupling"),
    ("C13", "100nF",     "Capacitor_SMD:C_0402_1005Metric",         "AMS1117 input decoupling"),

    ("LED1", "Red_0805",    "LED_SMD:LED_0805_2012Metric", "12V power indicator"),
    ("LED2", "Yellow_0805", "LED_SMD:LED_0805_2012Metric", "5V power indicator"),
    ("LED3", "Green_0805",  "LED_SMD:LED_0805_2012Metric", "3V3 power indicator"),
    ("LED4", "Blue_0805",   "LED_SMD:LED_0805_2012Metric", "Zone A active"),
    ("LED5", "Blue_0805",   "LED_SMD:LED_0805_2012Metric", "Zone B active"),
    ("LED6", "Blue_0805",   "LED_SMD:LED_0805_2012Metric", "Zone C active"),
    ("LED7", "Blue_0805",   "LED_SMD:LED_0805_2012Metric", "Zone D active"),

    ("SW1", "SPST_5A",      "Button_Switch_THT:SW_Rocker_SPST_Arcolectric-C1510ABAAA", "Power on/off — panel mount"),
    ("SW2", "DIP_4pos",     "Button_Switch_THT:SW_DIP_SPSTx04_Slide_9.78x4.72mm_W7.62mm_P2.54mm", "Zone enable DIP switch"),

    ("J_MST_A", "JST-XH-3", "Connector_JST:JST_XH_B3B-XH-A_1x03_P2.50mm_Vertical", "Moisture zone A"),
    ("J_MST_B", "JST-XH-3", "Connector_JST:JST_XH_B3B-XH-A_1x03_P2.50mm_Vertical", "Moisture zone B"),
    ("J_MST_C", "JST-XH-3", "Connector_JST:JST_XH_B3B-XH-A_1x03_P2.50mm_Vertical", "Moisture zone C"),
    ("J_MST_D", "JST-XH-3", "Connector_JST:JST_XH_B3B-XH-A_1x03_P2.50mm_Vertical", "Moisture zone D"),
    ("J_RLY_A", "JST-XH-3", "Connector_JST:JST_XH_B3B-XH-A_1x03_P2.50mm_Vertical", "Relay zone A"),
    ("J_RLY_B", "JST-XH-3", "Connector_JST:JST_XH_B3B-XH-A_1x03_P2.50mm_Vertical", "Relay zone B"),
    ("J_RLY_C", "JST-XH-3", "Connector_JST:JST_XH_B3B-XH-A_1x03_P2.50mm_Vertical", "Relay zone C"),
    ("J_RLY_D", "JST-XH-3", "Connector_JST:JST_XH_B3B-XH-A_1x03_P2.50mm_Vertical", "Relay zone D"),
    ("J_DHT",   "JST-XH-4", "Connector_JST:JST_XH_B4B-XH-A_1x04_P2.50mm_Vertical", "DHT22"),
    ("J_I2C_1", "JST-XH-4", "Connector_JST:JST_XH_B4B-XH-A_1x04_P2.50mm_Vertical", "I2C sensor 1"),
    ("J_I2C_2", "JST-XH-4", "Connector_JST:JST_XH_B4B-XH-A_1x04_P2.50mm_Vertical", "I2C sensor 2"),
    ("J_I2C_3", "JST-XH-4", "Connector_JST:JST_XH_B4B-XH-A_1x04_P2.50mm_Vertical", "I2C sensor 3"),
    ("J_PWR",   "DC-005",   "Connector_BarrelJack:BarrelJack_CUI_PJ-002AH_Horizontal", "12V DC barrel jack 2.1mm/5.5mm"),
    ("J_PI",    "Pi_Header_4pin", "Connector_PinHeader_2.54mm:PinHeader_1x04_P2.54mm_Vertical", "Pi UART + 5V — DNP"),

    ("SD1",  "MicroSD_Molex", "Connector_Card:microSD_HC_Hirose_DM3AT-SF-PEJM5", "MicroSD card slot"),

    ("TP1",  "TestPoint",  "TestPoint:TestPoint_THTPad_2.0x2.0mm_Drill1.0mm", "GND test point"),
    ("TP2",  "TestPoint",  "TestPoint:TestPoint_THTPad_2.0x2.0mm_Drill1.0mm", "3V3 test point"),
    ("TP3",  "TestPoint",  "TestPoint:TestPoint_THTPad_2.0x2.0mm_Drill1.0mm", "5V test point"),
    ("TP4",  "TestPoint",  "TestPoint:TestPoint_THTPad_2.0x2.0mm_Drill1.0mm", "12V test point"),
]

# ── Nets ──────────────────────────────────────────────────────────────────────
# Each net: (net_name, [(ref, pin), ...])

NETS = [
    ("+12V", [
        ("J_PWR", "1"), ("D1", "A"), ("SW1", "1"), ("SW1", "2"),
        ("U2", "IN+"), ("C1", "+"), ("R13", "1"),
        ("D14", "K"), ("D15", "K"), ("D16", "K"), ("D17", "K"), ("TP4", "1"),
    ]),
    ("+5V", [
        ("U2", "OUT+"), ("C2", "+"), ("U3", "IN"), ("C13", "1"),
        ("U1", "VIN"),
        ("J_RLY_A", "1"), ("J_RLY_B", "1"), ("J_RLY_C", "1"), ("J_RLY_D", "1"),
        ("R14", "1"), ("J_PI", "1"), ("TP3", "1"),
    ]),
    ("+3V3", [
        ("U3", "OUT"), ("C3", "+"),
        ("D2", "K"), ("D3", "K"), ("D4", "K"), ("D5", "K"),
        ("D6", "K"), ("D7", "K"), ("D8", "K"), ("D9", "K"),
        ("R5", "1"), ("R6", "1"), ("R7", "1"), ("R8", "1"),
        ("SD1", "VCC"), ("R15", "1"), ("TP2", "1"),
    ]),
    ("GND", [
        ("J_PWR", "2"), ("U2", "IN-"), ("U2", "OUT-"), ("U3", "GND"),
        ("U1", "GND"), ("C1", "-"), ("C2", "-"), ("C3", "-"),
        ("C4", "2"), ("C5", "2"), ("C6", "2"), ("C7", "2"), ("C8", "2"),
        ("C9", "2"), ("C10", "2"), ("C11", "2"), ("C12", "2"), ("C13", "2"),
        ("J_MST_A", "2"), ("J_MST_B", "2"), ("J_MST_C", "2"), ("J_MST_D", "2"),
        ("J_RLY_A", "2"), ("J_RLY_B", "2"), ("J_RLY_C", "2"), ("J_RLY_D", "2"),
        ("J_DHT", "2"), ("J_I2C_1", "2"), ("J_I2C_2", "2"), ("J_I2C_3", "2"),
        ("SD1", "GND"),
        ("D10", "A"), ("D11", "A"), ("D12", "A"), ("D13", "A"),
        ("D14", "A"), ("D15", "A"), ("D16", "A"), ("D17", "A"),
        ("R16", "2"), ("R17", "2"), ("R18", "2"), ("R19", "2"),
        ("LED1", "K"), ("LED2", "K"), ("LED3", "K"),
        ("LED4", "K"), ("LED5", "K"), ("LED6", "K"), ("LED7", "K"),
        ("J_PI", "2"), ("TP1", "1"),
    ]),
    ("MST_A_VCC", [("D2", "A"), ("J_MST_A", "1"), ("C4", "1")]),
    ("MST_B_VCC", [("D3", "A"), ("J_MST_B", "1"), ("C5", "1")]),
    ("MST_C_VCC", [("D4", "A"), ("J_MST_C", "1"), ("C6", "1")]),
    ("MST_D_VCC", [("D5", "A"), ("J_MST_D", "1"), ("C7", "1")]),
    ("MST_A_SIG", [("J_MST_A", "3"), ("U1", "GPIO32"), ("D10", "K")]),
    ("MST_B_SIG", [("J_MST_B", "3"), ("U1", "GPIO33"), ("D11", "K")]),
    ("MST_C_SIG", [("J_MST_C", "3"), ("U1", "GPIO34"), ("D12", "K")]),
    ("MST_D_SIG", [("J_MST_D", "3"), ("U1", "GPIO35"), ("D13", "K")]),
    ("RLY_A_SW",  [("U1", "GPIO25"), ("SW2", "ZA_IN")]),
    ("RLY_A_IN",  [("SW2", "ZA_OUT"), ("R1", "1"), ("R16", "1")]),
    ("RLY_A_OUT", [("R1", "2"), ("J_RLY_A", "3"), ("R9", "1")]),
    ("RLY_B_SW",  [("U1", "GPIO26"), ("SW2", "ZB_IN")]),
    ("RLY_B_IN",  [("SW2", "ZB_OUT"), ("R2", "1"), ("R17", "1")]),
    ("RLY_B_OUT", [("R2", "2"), ("J_RLY_B", "3"), ("R10", "1")]),
    ("RLY_C_SW",  [("U1", "GPIO13"), ("SW2", "ZC_IN")]),
    ("RLY_C_IN",  [("SW2", "ZC_OUT"), ("R3", "1"), ("R18", "1")]),
    ("RLY_C_OUT", [("R3", "2"), ("J_RLY_C", "3"), ("R11", "1")]),
    ("RLY_D_SW",  [("U1", "GPIO14"), ("SW2", "ZD_IN")]),
    ("RLY_D_IN",  [("SW2", "ZD_OUT"), ("R4", "1"), ("R19", "1")]),
    ("RLY_D_OUT", [("R4", "2"), ("J_RLY_D", "3"), ("R12", "1")]),
    ("ZONE_A_LED",[("R9",  "2"), ("LED4", "A")]),
    ("ZONE_B_LED",[("R10", "2"), ("LED5", "A")]),
    ("ZONE_C_LED",[("R11", "2"), ("LED6", "A")]),
    ("ZONE_D_LED",[("R12", "2"), ("LED7", "A")]),
    ("DHT_VCC",   [("D6", "A"), ("J_DHT", "1"), ("C8", "1")]),
    ("DHT_DATA",  [("J_DHT", "3"), ("U1", "GPIO27"), ("R5", "2")]),
    ("I2C_1_VCC", [("D7", "A"), ("J_I2C_1", "1"), ("C9", "1")]),
    ("I2C_2_VCC", [("D8", "A"), ("J_I2C_2", "1"), ("C10", "1")]),
    ("I2C_3_VCC", [("D9", "A"), ("J_I2C_3", "1"), ("C11", "1")]),
    ("SDA", [
        ("U1", "GPIO21"), ("R6", "2"),
        ("J_I2C_1", "3"), ("J_I2C_2", "3"), ("J_I2C_3", "3"),
    ]),
    ("SCL", [
        ("U1", "GPIO22"), ("R7", "2"),
        ("J_I2C_1", "4"), ("J_I2C_2", "4"), ("J_I2C_3", "4"),
    ]),
    ("SD_CS",   [("U1", "GPIO5"),  ("SD1", "CS"),   ("R8", "2")]),
    ("SD_MOSI", [("U1", "GPIO23"), ("SD1", "MOSI")]),
    ("SD_MISO", [("U1", "GPIO19"), ("SD1", "MISO")]),
    ("SD_SCK",  [("U1", "GPIO18"), ("SD1", "SCK")]),
    ("SD_VCC",  [("SD1", "VCC"),   ("C12", "1")]),
    ("LED1_NET",[("R13", "2"), ("LED1", "A")]),
    ("LED2_NET",[("R14", "2"), ("LED2", "A")]),
    ("LED3_NET",[("R15", "2"), ("LED3", "A")]),
    ("PI_TX",   [("J_PI", "3"), ("U1", "GPIO1")]),
    ("PI_RX",   [("J_PI", "4"), ("U1", "GPIO3")]),
    ("D1_INPUT",[("J_PWR", "1"), ("D1", "A")]),
    ("12V_SW_IN",[("D1", "K"), ("SW1", "1")]),
]

# ── Generator ─────────────────────────────────────────────────────────────────

def generate_netlist(output_path="node_board.net"):
    export = ET.Element("export", version="E")

    design = ET.SubElement(export, "design")
    ET.SubElement(design, "source").text = "NurseryHub Node Board"
    ET.SubElement(design, "date").text = str(date.today())
    ET.SubElement(design, "rev").text = "1.0"
    ET.SubElement(design, "tool").text = "NurseryHub generate_schematic.py"

    components_el = ET.SubElement(export, "components")
    for ref, value, footprint, desc in COMPONENTS:
        comp = ET.SubElement(components_el, "comp", ref=ref)
        ET.SubElement(comp, "value").text = value
        ET.SubElement(comp, "footprint").text = footprint
        ET.SubElement(comp, "description").text = desc

    nets_el = ET.SubElement(export, "nets")
    for code, (net_name, nodes) in enumerate(NETS, start=1):
        net = ET.SubElement(nets_el, "net", code=str(code), name=net_name)
        for ref, pin in nodes:
            ET.SubElement(net, "node", ref=ref, pin=pin)

    # pretty-print
    raw = ET.tostring(export, encoding="unicode")
    pretty = minidom.parseString(raw).toprettyxml(indent="  ")
    # strip the XML declaration minidom adds (KiCad adds its own)
    lines = pretty.split("\n")
    if lines[0].startswith("<?xml"):
        lines = lines[1:]
    output = '<?xml version="1.0" encoding="utf-8"?>\n' + "\n".join(lines)

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(output)

    print(f"Wrote {output_path}")
    print(f"  {len(COMPONENTS)} components")
    print(f"  {len(NETS)} nets")
    print()
    print("Next steps:")
    print("  1. Open KiCad PCB editor (pcbnew)")
    print("  2. File > Import Netlist > select node_board.net")
    print("  3. Click 'Update PCB' — components appear unplaced")
    print("  4. Place components and route traces")
    print()
    print("Footprints to verify in KiCad library:")
    print("  SW1  — rocker switch footprint may need manual selection")
    print("  SW2  — DIP switch footprint, verify pin count matches")
    print("  SD1  — MicroSD slot, verify against your chosen part")
    print("  J_PWR — barrel jack, verify orientation")
    print("  U1   — ESP32 uses 2x19 header footprint (not a module footprint)")


if __name__ == "__main__":
    generate_netlist()
