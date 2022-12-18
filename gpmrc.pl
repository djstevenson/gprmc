#!/usr/bin/env perl

# Takes GPS data from exiftool and creates video (well, will do the latter at some point)
# exiftool -ee /Users/davids/Desktop/220719_144732_219_FH.MP4 | carton exec -- gprmc.pl

# TODO POD documentation

use FindBin::libs;

while (my $line =~ <STDIN>) {
    chomp $line;
    next unless $line =~ /^Text                            :/;
    print $line, "\n";
}