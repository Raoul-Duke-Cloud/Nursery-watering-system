import Config

# This file is loaded automatically by Nerves when MIX_TARGET is set
# (e.g. MIX_TARGET=rpi0_2). It activates the on-site Pi hub configuration.
#
# Normal Mix builds (no MIX_TARGET) never load this file, so it has no
# effect on the central server or development environment.

import_config "nerves.exs"
