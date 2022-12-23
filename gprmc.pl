#!/usr/bin/env perl

use v5.36;

# Takes GPS data from exiftool and creates video (well, will do the latter at some point)
# exiftool -ee /Users/davids/Desktop/220719_144732_219_FH.MP4 | carton exec -- gprmc.pl

use FindBin::libs;
use DateTime;

binmode(STDIN);

while (my $line = <STDIN>) {
    chomp $line;

    # Line starts Text<spaces>: <some binary shiz>
    # Binary contains, GPS data in, for example:
    # $GPRMC,134747.300,A,5151.46603,N,00351.17490,W,34.711,92.16,190722,,,A*5B
    next unless $line =~ /
        ^
        Text\s+:\s          # Text indicator
        .*?                 # Skip other bin data
        \$GPRMC,            # Sentence identifier
        ([\d\.]+),          # UTC Time hhmmss.sss
        A,                  # A indicates valid (v = invalid)
        (\d+\.\d+),         # Latitude 5151.46603    ddmm.mmmmm
        ([NS]),             # Lat N or S
        (\d+\.\d+),         # Longitude 00351.18737  dddmm.mmmmm
        ([EW]),             # Long E or W
        (\d+\.\d+),         # Speed in knots
        (\d+\.\d+),         # Course, degrees (magnetic or true?)
        (\d\d\d\d\d\d),     # UTC Date DDMMYY
        ,,                  # Not used, Magnetic variation
        [ADE]               # Mode A=Autonomous, D=DGPS, E=DR, always A for NextBase
        \*[[:xdigit:]]{2}   # Checksum
    /x;

    my ($utc_time, $latitude, $ns, $longitude, $ew, $knots, $course, $date) = @{^CAPTURE};

    my $dt = format_datetime($date, $utc_time);

    my ($lat_deg, $long_deg) = format_lat_long($latitude, $ns, $longitude, $ew);
    my $mph = format_speed($knots);



    ## Altitude comes from GPGGA sentence
    # $GPGGA,134747.300,5151.46603,N,00351.17490,W,1,15,0.73,399.4,M,51.5,M,,*6C
    next unless $line =~ /
        ^
        Text\s+:\s          # Text indicator
        .*?                 # Skip other bin data
        \$GPGGA,            # Sentence identifier
        [\d\.]+,            # UTC Time hhmmss.sss
        \d+\.\d+,           # Latitude 5151.46603    ddmm.mmmmm
        [NS],               # Lat N or S
        \d+\.\d+,           # Longitude 00351.18737  dddmm.mmmmm
        [EW],               # Long E or W
        1,                  # Fix quality (want 1)
        \d\d,               # Satellite count
        [\d\.]+,            # Horizontal dilution
        ([\d\.]+),          # Height in metres
        M,                  # Not used, indicates metres?
        [\d\.]+,            # Geoidal separation (metres)
        M,,                 # Not used, indicates metres?
        \*[[:xdigit:]]{2}   # Checksum
    /x;

    my ($altitude) = @{^CAPTURE};

    printf("DT=%s (%.5f, %.5f) : V=%d C=%d˚ A=%.1f\n", $dt, $lat_deg, $long_deg, round($mph), round($course), $altitude);
}

sub round($f) {
    return int($f+0.5);
}

sub format_datetime($date, $time) {
    # $date is DDMMYY
    # $time is hhmmss.sss
    # All in UTC

    my ($day, $mon, $year) = $date =~ /^(\d\d)(\d\d)(\d\d)$/;
    my ($hour, $min, $sec) = $time =~ /^(\d\d)(\d\d)(\d\d\.\d\d\d)$/;

    return DateTime->new(
        year       => 2000 + $year,
        month      => $mon,
        day        => $day,
        hour       => $hour,
        minute     => $min,
        second     => int($sec),
        nanosecond => int(($sec-int($sec)) * 1_000_000),
        time_zone  => 'UTC',
    );
}

sub format_speed($knots) {
    return $knots * 1.15077945;
}

sub format_lat_long($lat, $ns, $long, $ew) {

    # Longitude is in format ddmm.mmmmm
    # dd = Degrees (unsigned)
    # mm.mmmmm = Minutes
    # So degress in decimal is
    #  dd + (mm.mmmmm)/60
    # Then apply sign from N/S.

    # Longitude is same, except three digits
    # for degrees.

    my ($latitude, $longitude);
    if ($lat =~ /^(\d\d)(\d+.\d+)$/) {
        $latitude = $1 + $2/60;
        $latitude *= $ns eq 'N' ? 1 : -1;
    }
    else {
        die "Invalid latitude $lat";
    }
    if ($long =~ /^(\d\d\d)(\d+.\d+)$/) {
        $longitude = $1 + $2/60;
        $longitude *= $ew eq 'W' ? -1 : 1;
    }
    else {
        die "Invalid longitude $long";
    }

    return ($latitude, $longitude);
}
