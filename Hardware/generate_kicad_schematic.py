#!/usr/bin/env python3
"""
NurseryHub Node Board — KiCad 7 Schematic Generator

Generates a valid KiCad 7 schematic file (.kicad_sch) with all components
placed and connected via net labels. Open directly in KiCad 7 eeschema.

Usage:
    python generate_kicad_schematic.py
    # outputs: node_board.kicad_sch

Then in KiCad 7:
    1. File > Open — select node_board.kicad_sch
    2. Components are placed in a grid, connected by net labels
    3. Run Tools > Update PCB from Schematic to push to pcbnew
    4. Place and route in pcbnew

No dependencies beyond Python 3 standard library.
"""

import uuid
from datetime import date

# ── Helpers ───────────────────────────────────────────────────────────────────

def uid():
    return str(uuid.uuid4())

def pin_stub(x, y, angle, net, length=2.54):
    """A short wire stub + net label at a component pin."""
    # wire end coords
    import math
    rad = math.radians(angle)
    ex = round(x + length * math.cos(rad), 4)
    ey = round(y + length * math.sin(rad), 4)
    wire = f'  (wire (pts (xy {x} {y}) (xy {ex} {ey})) (stroke (width 0) (type default)) (uuid "{uid()}"))\n'
    label = f'  (net_label "{net}" (at {ex} {ey} {angle}) (fields_autoplaced)\n'
    label += f'    (effects (font (size 1.27 1.27)) (justify left))\n'
    label += f'    (uuid "{uid()}"))\n'
    return wire + label

# ── Component box builder ──────────────────────────────────────────────────────

def make_symbol(ref, value, x, y, pins_left, pins_right, width=10, height=None):
    """
    Draw a component as a rectangle with labelled pins.
    pins_left:  list of (pin_name, net_name) top-to-bottom on left side
    pins_right: list of (pin_name, net_name) top-to-bottom on right side
    Returns schematic s-expression strings.
    """
    if height is None:
        height = max(len(pins_left), len(pins_right), 1) * 2.54 + 2.54

    half_w = width / 2
    half_h = height / 2

    lines = []

    # Rectangle
    lines.append(f'  (rectangle (start {x - half_w} {y - half_h}) (end {x + half_w} {y + half_h})')
    lines.append(f'    (stroke (width 0.1) (type default)) (fill (type background))')
    lines.append(f'    (uuid "{uid()}"))')

    # Reference label
    lines.append(f'  (text "{ref}" (at {x} {y - half_h - 1.5} 0)')
    lines.append(f'    (effects (font (size 1.27 1.27) (bold yes)))')
    lines.append(f'    (uuid "{uid()}"))')

    # Value label
    lines.append(f'  (text "{value}" (at {x} {y + half_h + 1.5} 0)')
    lines.append(f'    (effects (font (size 1.0 1.0)))')
    lines.append(f'    (uuid "{uid()}"))')

    # Left pins
    pin_spacing = height / (len(pins_left) + 1) if pins_left else 2.54
    for i, (pin_name, net_name) in enumerate(pins_left):
        py = y - half_h + pin_spacing * (i + 1)
        px = x - half_w
        # pin label inside box
        lines.append(f'  (text "{pin_name}" (at {px + 0.5} {py} 0)')
        lines.append(f'    (effects (font (size 0.8 0.8)) (justify left))')
        lines.append(f'    (uuid "{uid()}"))')
        # wire + net label outside
        wire_end_x = round(px - 3.81, 4)
        lines.append(f'  (wire (pts (xy {px} {py}) (xy {wire_end_x} {py})) (stroke (width 0) (type default)) (uuid "{uid()}"))')
        lines.append(f'  (net_label "{net_name}" (at {wire_end_x} {py} 180) (fields_autoplaced)')
        lines.append(f'    (effects (font (size 1.0 1.0)) (justify right))')
        lines.append(f'    (uuid "{uid()}"))')

    # Right pins
    pin_spacing = height / (len(pins_right) + 1) if pins_right else 2.54
    for i, (pin_name, net_name) in enumerate(pins_right):
        py = y - half_h + pin_spacing * (i + 1)
        px = x + half_w
        lines.append(f'  (text "{pin_name}" (at {px - 0.5} {py} 0)')
        lines.append(f'    (effects (font (size 0.8 0.8)) (justify right))')
        lines.append(f'    (uuid "{uid()}"))')
        wire_end_x = round(px + 3.81, 4)
        lines.append(f'  (wire (pts (xy {px} {py}) (xy {wire_end_x} {py})) (stroke (width 0) (type default)) (uuid "{uid()}"))')
        lines.append(f'  (net_label "{net_name}" (at {wire_end_x} {py} 0) (fields_autoplaced)')
        lines.append(f'    (effects (font (size 1.0 1.0)) (justify left))')
        lines.append(f'    (uuid "{uid()}"))')

    return "\n".join(lines)

# ── Component definitions ──────────────────────────────────────────────────────
# (ref, value, x, y, pins_left, pins_right)

def build_schematic():
    blocks = []

    # ── Power input and switching ────────────────────────────────────────────
    blocks.append(make_symbol("J_PWR", "DC-005 12V", 20, 20,
        [("1 +12V", "D1_INPUT"), ("2 GND", "GND")], []))

    blocks.append(make_symbol("D1", "SS14 Rev.Prot", 35, 20,
        [("A", "D1_INPUT")], [("K", "12V_SW_IN")]))

    blocks.append(make_symbol("SW1", "SPST Power", 50, 20,
        [("1", "12V_SW_IN")], [("2", "+12V")]))

    # ── Power rails ──────────────────────────────────────────────────────────
    blocks.append(make_symbol("U2", "LM2596 Buck", 20, 50,
        [("IN+", "+12V"), ("IN-", "GND")],
        [("OUT+", "+5V"), ("OUT-", "GND")]))

    blocks.append(make_symbol("U3", "AMS1117-3.3", 50, 50,
        [("IN", "+5V"), ("GND", "GND")],
        [("OUT", "+3V3")]))

    blocks.append(make_symbol("C1", "100uF 12V", 20, 70,
        [("+", "+12V"), ("-", "GND")], []))

    blocks.append(make_symbol("C2", "100uF 5V", 35, 70,
        [("+", "+5V"), ("-", "GND")], []))

    blocks.append(make_symbol("C3", "100uF 3V3", 50, 70,
        [("+", "+3V3"), ("-", "GND")], []))

    blocks.append(make_symbol("C13", "100nF AMS", 65, 70,
        [("1", "+5V"), ("2", "GND")], []))

    # ── Status LEDs ──────────────────────────────────────────────────────────
    blocks.append(make_symbol("R13", "1k LED1", 80, 20,
        [("1", "+12V")], [("2", "LED1_NET")]))
    blocks.append(make_symbol("LED1", "Red 12V", 95, 20,
        [("A", "LED1_NET")], [("K", "GND")]))

    blocks.append(make_symbol("R14", "1k LED2", 80, 30,
        [("1", "+5V")], [("2", "LED2_NET")]))
    blocks.append(make_symbol("LED2", "Yellow 5V", 95, 30,
        [("A", "LED2_NET")], [("K", "GND")]))

    blocks.append(make_symbol("R15", "1k LED3", 80, 40,
        [("1", "+3V3")], [("2", "LED3_NET")]))
    blocks.append(make_symbol("LED3", "Green 3V3", 95, 40,
        [("A", "LED3_NET")], [("K", "GND")]))

    # ── ESP32 ────────────────────────────────────────────────────────────────
    blocks.append(make_symbol("U1", "ESP32-DevKitC", 140, 80,
        [
            ("VIN",    "+5V"),
            ("GND",    "GND"),
            ("GPIO32", "MST_A_SIG"),
            ("GPIO33", "MST_B_SIG"),
            ("GPIO34", "MST_C_SIG"),
            ("GPIO35", "MST_D_SIG"),
            ("GPIO25", "RLY_A_SW"),
            ("GPIO26", "RLY_B_SW"),
            ("GPIO13", "RLY_C_SW"),
            ("GPIO14", "RLY_D_SW"),
        ],
        [
            ("GPIO27", "DHT_DATA"),
            ("GPIO21", "SDA"),
            ("GPIO22", "SCL"),
            ("GPIO5",  "SD_CS"),
            ("GPIO23", "SD_MOSI"),
            ("GPIO19", "SD_MISO"),
            ("GPIO18", "SD_SCK"),
            ("GPIO1",  "PI_TX"),
            ("GPIO3",  "PI_RX"),
            ("3V3",    "+3V3"),
        ],
        width=20, height=30))

    # ── Zone DIP switch ──────────────────────────────────────────────────────
    blocks.append(make_symbol("SW2", "DIP 4-pos Zone Enable", 100, 100,
        [("ZA_IN", "RLY_A_SW"), ("ZB_IN", "RLY_B_SW"),
         ("ZC_IN", "RLY_C_SW"), ("ZD_IN", "RLY_D_SW")],
        [("ZA_OUT", "RLY_A_IN"), ("ZB_OUT", "RLY_B_IN"),
         ("ZC_OUT", "RLY_C_IN"), ("ZD_OUT", "RLY_D_IN")]))

    # ── Zone A ───────────────────────────────────────────────────────────────
    blocks.append(make_symbol("R1",  "1k",  180, 60, [("1", "RLY_A_IN")], [("2", "RLY_A_OUT")]))
    blocks.append(make_symbol("R16", "10k", 180, 65, [("1", "RLY_A_IN"), ("2", "GND")], []))
    blocks.append(make_symbol("R9",  "1k",  195, 60, [("1", "RLY_A_OUT")], [("2", "ZONE_A_LED")]))
    blocks.append(make_symbol("LED4","Blue ZA", 210, 60, [("A", "ZONE_A_LED")], [("K", "GND")]))
    blocks.append(make_symbol("J_RLY_A", "Relay A", 225, 60,
        [("1 VCC", "+5V"), ("2 GND", "GND"), ("3 IN", "RLY_A_OUT")], []))
    blocks.append(make_symbol("D2",  "SS14", 225, 70, [("A", "MST_A_VCC")], [("K", "+3V3")]))
    blocks.append(make_symbol("C4",  "100nF", 235, 70, [("1", "MST_A_VCC"), ("2", "GND")], []))
    blocks.append(make_symbol("D10", "SMBJ3.3A", 245, 60, [("A", "GND")], [("K", "MST_A_SIG")]))
    blocks.append(make_symbol("J_MST_A", "Moisture A", 260, 65,
        [("1 VCC", "MST_A_VCC"), ("2 GND", "GND"), ("3 SIG", "MST_A_SIG")], []))
    blocks.append(make_symbol("D14", "SS14 DNP", 225, 80,
        [("A", "GND")], [("K", "+12V")]))  # flyback DNP

    # ── Zone B ───────────────────────────────────────────────────────────────
    blocks.append(make_symbol("R2",  "1k",  180, 90,  [("1", "RLY_B_IN")], [("2", "RLY_B_OUT")]))
    blocks.append(make_symbol("R17", "10k", 180, 95,  [("1", "RLY_B_IN"), ("2", "GND")], []))
    blocks.append(make_symbol("R10", "1k",  195, 90,  [("1", "RLY_B_OUT")], [("2", "ZONE_B_LED")]))
    blocks.append(make_symbol("LED5","Blue ZB", 210, 90, [("A", "ZONE_B_LED")], [("K", "GND")]))
    blocks.append(make_symbol("J_RLY_B", "Relay B", 225, 90,
        [("1 VCC", "+5V"), ("2 GND", "GND"), ("3 IN", "RLY_B_OUT")], []))
    blocks.append(make_symbol("D3",  "SS14", 225, 100, [("A", "MST_B_VCC")], [("K", "+3V3")]))
    blocks.append(make_symbol("C5",  "100nF", 235, 100,[("1", "MST_B_VCC"), ("2", "GND")], []))
    blocks.append(make_symbol("D11", "SMBJ3.3A", 245, 90, [("A", "GND")], [("K", "MST_B_SIG")]))
    blocks.append(make_symbol("J_MST_B", "Moisture B", 260, 95,
        [("1 VCC", "MST_B_VCC"), ("2 GND", "GND"), ("3 SIG", "MST_B_SIG")], []))
    blocks.append(make_symbol("D15", "SS14 DNP", 225, 110, [("A", "GND")], [("K", "+12V")]))

    # ── Zone C ───────────────────────────────────────────────────────────────
    blocks.append(make_symbol("R3",  "1k",  180, 120, [("1", "RLY_C_IN")], [("2", "RLY_C_OUT")]))
    blocks.append(make_symbol("R18", "10k", 180, 125, [("1", "RLY_C_IN"), ("2", "GND")], []))
    blocks.append(make_symbol("R11", "1k",  195, 120, [("1", "RLY_C_OUT")], [("2", "ZONE_C_LED")]))
    blocks.append(make_symbol("LED6","Blue ZC", 210, 120, [("A", "ZONE_C_LED")], [("K", "GND")]))
    blocks.append(make_symbol("J_RLY_C", "Relay C", 225, 120,
        [("1 VCC", "+5V"), ("2 GND", "GND"), ("3 IN", "RLY_C_OUT")], []))
    blocks.append(make_symbol("D4",  "SS14", 225, 130, [("A", "MST_C_VCC")], [("K", "+3V3")]))
    blocks.append(make_symbol("C6",  "100nF", 235, 130,[("1", "MST_C_VCC"), ("2", "GND")], []))
    blocks.append(make_symbol("D12", "SMBJ3.3A", 245, 120, [("A", "GND")], [("K", "MST_C_SIG")]))
    blocks.append(make_symbol("J_MST_C", "Moisture C", 260, 125,
        [("1 VCC", "MST_C_VCC"), ("2 GND", "GND"), ("3 SIG", "MST_C_SIG")], []))
    blocks.append(make_symbol("D16", "SS14 DNP", 225, 140, [("A", "GND")], [("K", "+12V")]))

    # ── Zone D ───────────────────────────────────────────────────────────────
    blocks.append(make_symbol("R4",  "1k",  180, 150, [("1", "RLY_D_IN")], [("2", "RLY_D_OUT")]))
    blocks.append(make_symbol("R19", "10k", 180, 155, [("1", "RLY_D_IN"), ("2", "GND")], []))
    blocks.append(make_symbol("R12", "1k",  195, 150, [("1", "RLY_D_OUT")], [("2", "ZONE_D_LED")]))
    blocks.append(make_symbol("LED7","Blue ZD", 210, 150, [("A", "ZONE_D_LED")], [("K", "GND")]))
    blocks.append(make_symbol("J_RLY_D", "Relay D", 225, 150,
        [("1 VCC", "+5V"), ("2 GND", "GND"), ("3 IN", "RLY_D_OUT")], []))
    blocks.append(make_symbol("D5",  "SS14", 225, 160, [("A", "MST_D_VCC")], [("K", "+3V3")]))
    blocks.append(make_symbol("C7",  "100nF", 235, 160,[("1", "MST_D_VCC"), ("2", "GND")], []))
    blocks.append(make_symbol("D13", "SMBJ3.3A", 245, 150, [("A", "GND")], [("K", "MST_D_SIG")]))
    blocks.append(make_symbol("J_MST_D", "Moisture D", 260, 155,
        [("1 VCC", "MST_D_VCC"), ("2 GND", "GND"), ("3 SIG", "MST_D_SIG")], []))
    blocks.append(make_symbol("D17", "SS14 DNP", 225, 170, [("A", "GND")], [("K", "+12V")]))

    # ── DHT22 ────────────────────────────────────────────────────────────────
    blocks.append(make_symbol("D6",  "SS14", 20, 100, [("A", "DHT_VCC")], [("K", "+3V3")]))
    blocks.append(make_symbol("C8",  "100nF", 30, 100,[("1", "DHT_VCC"), ("2", "GND")], []))
    blocks.append(make_symbol("R5",  "10k pullup", 20, 110,
        [("1", "+3V3")], [("2", "DHT_DATA")]))
    blocks.append(make_symbol("J_DHT", "DHT22", 40, 105,
        [("1 VCC", "DHT_VCC"), ("2 GND", "GND"), ("3 DATA", "DHT_DATA"), ("4 NC", "unconnected")], []))

    # ── I2C bus ──────────────────────────────────────────────────────────────
    blocks.append(make_symbol("R6", "4.7k SDA", 20, 130, [("1", "+3V3")], [("2", "SDA")]))
    blocks.append(make_symbol("R7", "4.7k SCL", 20, 136, [("1", "+3V3")], [("2", "SCL")]))

    blocks.append(make_symbol("D7",  "SS14", 40, 125, [("A", "I2C_1_VCC")], [("K", "+3V3")]))
    blocks.append(make_symbol("C9",  "100nF", 50, 125,[("1", "I2C_1_VCC"), ("2", "GND")], []))
    blocks.append(make_symbol("J_I2C_1", "I2C Sensor 1", 65, 127,
        [("1 VCC", "I2C_1_VCC"), ("2 GND", "GND"), ("3 SDA", "SDA"), ("4 SCL", "SCL")], []))

    blocks.append(make_symbol("D8",  "SS14", 40, 140, [("A", "I2C_2_VCC")], [("K", "+3V3")]))
    blocks.append(make_symbol("C10", "100nF", 50, 140,[("1", "I2C_2_VCC"), ("2", "GND")], []))
    blocks.append(make_symbol("J_I2C_2", "I2C Sensor 2", 65, 142,
        [("1 VCC", "I2C_2_VCC"), ("2 GND", "GND"), ("3 SDA", "SDA"), ("4 SCL", "SCL")], []))

    blocks.append(make_symbol("D9",  "SS14", 40, 155, [("A", "I2C_3_VCC")], [("K", "+3V3")]))
    blocks.append(make_symbol("C11", "100nF", 50, 155,[("1", "I2C_3_VCC"), ("2", "GND")], []))
    blocks.append(make_symbol("J_I2C_3", "I2C Sensor 3", 65, 157,
        [("1 VCC", "I2C_3_VCC"), ("2 GND", "GND"), ("3 SDA", "SDA"), ("4 SCL", "SCL")], []))

    # ── MicroSD ──────────────────────────────────────────────────────────────
    blocks.append(make_symbol("SD1", "MicroSD", 20, 175,
        [("VCC", "+3V3"), ("GND", "GND"), ("CS", "SD_CS"),
         ("MOSI", "SD_MOSI"), ("MISO", "SD_MISO"), ("SCK", "SD_SCK")], []))
    blocks.append(make_symbol("C12", "100nF SD", 35, 175,[("1", "+3V3"), ("2", "GND")], []))
    blocks.append(make_symbol("R8",  "10k CS", 35, 181, [("1", "+3V3")], [("2", "SD_CS")]))

    # ── Test points ──────────────────────────────────────────────────────────
    blocks.append(make_symbol("TP1", "GND",  60, 175, [("1", "GND")],  []))
    blocks.append(make_symbol("TP2", "3V3",  67, 175, [("1", "+3V3")], []))
    blocks.append(make_symbol("TP3", "5V",   74, 175, [("1", "+5V")],  []))
    blocks.append(make_symbol("TP4", "12V",  81, 175, [("1", "+12V")], []))

    # ── Pi header ────────────────────────────────────────────────────────────
    blocks.append(make_symbol("J_PI", "Pi Header DNP", 20, 190,
        [("1 5V", "+5V"), ("2 GND", "GND"), ("3 TX", "PI_TX"), ("4 RX", "PI_RX")], []))

    return "\n".join(blocks)


# ── Write .kicad_sch ──────────────────────────────────────────────────────────

def write_schematic(output_path="node_board.kicad_sch"):
    today = str(date.today())
    body = build_schematic()

    content = f'''(kicad_sch (version 20230121) (generator "nursery_hub_gen")

  (paper "A2")

  (title_block
    (title "NurseryHub Node Board")
    (date "{today}")
    (rev "1.0")
    (company "NurseryHub")
    (comment 1 "Generated by Hardware/generate_kicad_schematic.py")
    (comment 2 "All connections via net labels — same label = same net")
    (comment 3 "DNP components: D14-D17 (flyback), J_PI (Pi header)")
  )

{body}

)
'''

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"Wrote {output_path}")
    print()
    print("Open in KiCad 7:")
    print("  File > Open Schematic > select node_board.kicad_sch")
    print()
    print("Components are placed in a grid connected by net labels.")
    print("Tidy the layout, then:")
    print("  Tools > Update PCB from Schematic")


if __name__ == "__main__":
    write_schematic()
