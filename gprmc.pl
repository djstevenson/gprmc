#!/usr/bin/env perl
use Mojo::Base -signatures;
use v5.42;
use utf8;

# Takes GPS data from exiftool and creates video (well, will do the latter at some point)
# exiftool -ee -X -n /Users/davids/Desktop/220719_144732_219_FH.MP4 | carton exec -- gprmc.pl

use FindBin::libs;
use DateTime;
use DateTime::Format::ISO8601::Format;
use Template;
use Math::Trig qw(deg2rad);

binmode STDIN, ':encoding(UTF-8)';

# Load data assuming our input is from exiftool, speciically
# exiftool -ee -n /Users/davids/Desktop/220719_144732_219_FH.MP4 | carton exec -- gprmc.pl

#
#
# A block of GPS data will typically look like this:
# GPS Altitude                    : 92.1
# GPS Dilution Of Precision       : 0.86
# GPS Date/Time                   : 2026:06:27 17:00:20.900Z
# GPS Latitude                    : 51.8941496666667
# GPS Longitude                   : -1.22875083333333
# GPS Satellites                  : 12
# GPS Speed                       : 77.863636
# GPS Track                       : 258.63
# Sample Time                     : 179.9
# Sample Duration                 : 0.1
# Accelerometer Data              : -44 -446 -414 1640 -65 181 -250 -178 -650 1908 143 189 -458 74 -604 2042 24 -15 -498 222 -652 2018 -359 -387 -446 -274 -458 2379 158 -401 -480 -268 -118 2372 233 -557 -146 -38 -78 2013 -46 -777 22 -96 -116 1803 20 -719 213 -237 -223 1963 525 -394 49 -205 -149 1756 374 -352 248 32 -524 1608 44 -454 330 -6 -744 1930 334 -219 130 32 -730 2481 810 137 -110 -160 -450 2466 440 -42 -114 -10 -420 2416 43 -350 -70 -26 -256 2662 465 -187 -108 -334 204 2536 602 -143 -176 -236 320 1902 90 -425 230 -86 128 1812 390 -284 58 114 88 1822 770 46 -192 124 -168 1475 316 -166 -244 -264 -480 1454 29 -448 -37 187 -797 2219 377 -395 19 291 -589 2364 140 -534 36 162 -448 2530 76 -507 254 -316 -144 2749 322 -393 80 90 68 2570 230 -270 154 -200 212 2141 -28 -356 80 -188 142 1976 110 -195 50 18 60 2001 403 -46 -104 230 -56 1840 297 -114 -64 166 -310 1923 290 -103 -132 6 -452 2048 25 -289 -52 78 -484 2394 108 -335 12 306 -386 2622 125 -309 43 129 -115 2626 15 -338 -169 61 71 2586 87 -310 -68 -84 208 2433 57 -403 -92 62 234 2282 239 -323 -72 120 204 2102 266 -323 -214 34 208 1833 178 -413
#
# Sometimes, we seem to get partial blocks repeated.  So we're going to process this by
# assigning the latest value of each field to variables and then just output the latest
# values when we see a GPS Track line, which seems to be the last interesting line of good blocks.

my @pos_history;  # ring buffer of positions; 10 samples = ~1 second at 0.1s/sample
my %latest;
my $fileno = 1;
my $gradient_age = 25; # 10 samples per second.
my $gradient = 0;
my $limit = 30;
while (defined(my $line = <STDIN>)) {
    chomp $line;

    if ($line =~ /^GPS\s+(.+?)\s*:\s*(.+)$/) {
        my ($key, $value) = ($1, $2);
        $key =~ s/\W/_/g;
        $latest{$key} = $value;
        if ($key eq 'Track') {
            $latest{Limit} = $limit;
            if (@pos_history == $gradient_age) {
                my $old = $pos_history[0];
                $gradient = int(0.5 + gradient_percent(
                    $old->{Latitude}, $old->{Longitude}, $old->{Altitude},
                    $latest{Latitude}, $latest{Longitude}, $latest{Altitude}
                )) if defined $old->{Latitude} && defined $old->{Longitude} && defined $old->{Altitude};
            }
            $latest{Gradient} = $gradient;
            push @pos_history, {
                Latitude  => $latest{Latitude},
                Longitude => $latest{Longitude},
                Altitude  => $latest{Altitude},
            };
            shift @pos_history if @pos_history > $gradient_age;
            writeHTML($fileno, \%latest);
            $fileno++;
        }
    }
}

sub writeHTML($fileno, $latest) {
    mkdir 'output' unless -d 'output';
    my $dir_no = sprintf('%02d', int($fileno / 100));
    mkdir "output/$dir_no" unless -d "output/$dir_no";
    my $html_filename = sprintf('output/%s/gauges%04d.html', $dir_no, $fileno);
    open(my $fh, '>:utf8', $html_filename);


    my $tt2 = Template->new({ INCLUDE_PATH => 'templates' });
    $tt2->process('main.tt2', $latest, $fh) or die $tt2->error();
}

sub haversine_m {
    my ($lat1, $lon1, $lat2, $lon2) = @_;

    my $r = 6_371_000; # Earth radius in metres

    my $phi1 = deg2rad($lat1);
    my $phi2 = deg2rad($lat2);
    my $dphi = deg2rad($lat2 - $lat1);
    my $dlambda = deg2rad($lon2 - $lon1);

    my $a = sin($dphi / 2) ** 2
          + cos($phi1) * cos($phi2) * sin($dlambda / 2) ** 2;
    my $c = 2 * atan2(sqrt($a), sqrt(1 - $a));

    return $r * $c;
}

sub gradient_percent {
    my ($lat1, $lon1, $alt1, $lat2, $lon2, $alt2) = @_;

    my $dist = haversine_m($lat1, $lon1, $lat2, $lon2);
    return 0 if $dist < 1; # avoid madness when stationary / tiny movement

    return (($alt2 - $alt1) / $dist) * 100;
}
