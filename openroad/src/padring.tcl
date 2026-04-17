# Copyright (c) 2024 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors:
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>

#
# Pad placement is driven by bondpad_centroids.csv.
# Each row has: instance_name, net, x_um, y_um (bondpad centroid in OR coords).
# Bondpad centroids sit at padBond/2 from each chip edge, so:
#   WEST  (x = padBond/2): IO_WEST,  location = y - padW/2
#   SOUTH (y = padBond/2): IO_SOUTH, location = x - padW/2
#   EAST  (x = chipW - padBond/2): IO_EAST,  location = y - padW/2
#   NORTH (y = chipH - padBond/2): IO_NORTH, location = x - padW/2

make_io_sites -horizontal_site sg13g2_ioSite \
    -vertical_site sg13g2_ioSite \
    -corner_site sg13g2_ioSite \
    -offset $padBond \
    -rotation_horizontal R0 \
    -rotation_vertical R0 \
    -rotation_corner R0

##########################################################################
# Place pads from CSV                                                     #
##########################################################################
set csvFile "src/bondpad_centroids.csv"
set fp [open $csvFile r]
gets $fp ;# skip header line

while {[gets $fp line] >= 0} {
    set fields    [split $line ","]
    set inst_name [lindex $fields 0]
    set x         [expr {double([lindex $fields 2])}]
    set y         [expr {double([lindex $fields 3])}]

    # Strip the bondpad prefix to get the IO-cell instance name
    set pad_name  [string map {"IO_BOND_" ""} $inst_name]

    if {$x <= $padBond} {
        place_pad -row IO_WEST  -location [expr {$y - $padW / 2.0}] $pad_name
    } elseif {$y <= $padBond} {
        place_pad -row IO_SOUTH -location [expr {$x - $padW / 2.0}] $pad_name
    } elseif {$x >= [expr {$chipW - $padBond}]} {
        place_pad -row IO_EAST  -location [expr {$y - $padW / 2.0}] $pad_name
    } else {
        place_pad -row IO_NORTH -location [expr {$x - $padW / 2.0}] $pad_name
    }
}
close $fp

# Fill in the rest of the padring
place_corners $iocorner

place_io_fill -row IO_NORTH {*}$iofill
place_io_fill -row IO_SOUTH {*}$iofill
place_io_fill -row IO_WEST  {*}$iofill
place_io_fill -row IO_EAST  {*}$iofill

# Connect built-in power rings
connect_by_abutment

# Bondpad as separate cell placed in OpenROAD:
# place the bonding pad relative to the IO cell
place_bondpad -bond $bondPadCell -offset {5.0 -70.0} pad_*

# remove rows created by via make_io_sites as they are no longer needed
remove_io_rows
