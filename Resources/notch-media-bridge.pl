#!/usr/bin/perl
#
# Host process for the NotchIsland media bridge.
#
# macOS only answers MediaRemote queries for processes whose main executable is
# signed by Apple. /usr/bin/perl is such a binary, so the app runs this script
# and hands it the bridge library to load. The library's constructor takes over
# the process immediately and never returns, which is why there is no further
# perl code below.
#
# Usage: notch-media-bridge.pl /path/to/libNotchMediaBridge.dylib

use strict;
use warnings;
use DynaLoader ();

my $library = shift @ARGV;

die "usage: notch-media-bridge.pl <path-to-bridge-library>\n"
    unless defined $library;
die "bridge library not found: $library\n"
    unless -f $library;

# 0x01 is RTLD_GLOBAL, matching how the library expects to be loaded.
DynaLoader::dl_load_file($library, 0x01)
    or die "failed to load bridge library: " . (DynaLoader::dl_error() // 'unknown error') . "\n";

# Unreachable: the constructor calls dispatch_main() and never returns. If
# control does arrive here, the library loaded but did not start.
die "bridge library loaded but did not start\n";
