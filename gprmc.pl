#!/usr/bin/env perl

use v5.36;

# Takes GPS data from exiftool and creates video (well, will do the latter at some point)
# exiftool -ee /Users/davids/Desktop/220719_144732_219_FH.MP4 | carton exec -- gprmc.pl

use FindBin::libs;
use DateTime;
use Math::Trig;

binmode(STDIN);

my $file_no = 1;
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

    my $lat_long = format_lat_long($latitude, $ns, $longitude, $ew);
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

    write_html($file_no, {
        date_time => $dt,
        lat_long  => $lat_long,
        speed     => $mph,
        course    => $course,
        altitude  => $altitude,
    });

    $file_no++;
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

    return { lat => $latitude, long => $longitude};
}

sub gauge_lat_long($lat_long) {
    my $lat      = $lat_long->{lat};
    my $long     = $lat_long->{long};

    my $abs_lat  = sprintf('%.4f', abs($lat));
    my $abs_long = sprintf('%.4f', abs($long));

    my $ns       = $lat  < 0 ? 'S' : 'N';
    my $ew       = $long < 0 ? 'W' : 'E';

    return <<HTML;
<div>
    <svg width="100" height="100">
        <path d="M0 0 L0 100 L100 100 L100 0 Z" stroke="black" stroke-width="1" fill="none"/>

        <text x="75" y="25" fill="#333333" font-family="Helvetica, sans-serif" dominant-baseline="middle" text-anchor="end" font-size="1em" font-weight="bold">${abs_lat}˚</text>
        <text x="90" y="25" fill="#333333" font-family="Helvetica, sans-serif" dominant-baseline="middle" text-anchor="end" font-size="1em" font-weight="bold">${ns}</text>
        <text x="75" y="50" fill="#333333" font-family="Helvetica, sans-serif" dominant-baseline="middle" text-anchor="end" font-size="1em" font-weight="bold">${abs_long}˚</text>
        <text x="90" y="50" fill="#333333" font-family="Helvetica, sans-serif" dominant-baseline="middle" text-anchor="end" font-size="1em" font-weight="bold">$ew</text>
        <text x="75" y="75" fill="#333333" font-family="Helvetica, sans-serif" dominant-baseline="middle" text-anchor="end" font-size="1em" font-weight="normal">321.4m</text>
        <text x="90" y="75" fill="#333333" font-family="Helvetica, sans-serif" dominant-baseline="middle" text-anchor="end" font-size="1em" font-weight="normal">&uarr;</text>
    </svg>
</div>
HTML
}

sub gauge_speed($speed) {
    my $round_speed = round($speed);

    my $dial_gap_deg = 90;
    my $dial_angle   = 1.0 - ($dial_gap_deg / 360.0);
    my $radius       = 40;
    my $panel_width  = 100;
    my $half_width   = $panel_width/2.0;
    my $min_speed    = 0;
    my $max_speed    = 70;

    my $half_gap_rad = pi * (1-$dial_angle);

    my $x_offset     = $radius * sin($half_gap_rad);
    my $y_offset     = $radius * cos($half_gap_rad);

    my $start_x      = $half_width - $x_offset;
    my $start_y      = $half_width + $y_offset;
    my $end_x        = $half_width + $x_offset;
    my $end_y        = $half_width + $y_offset;
    
    my $angle_min    = $dial_gap_deg/2.0;
    my $angle_max    = 360.0 - $angle_min;

    my $current_value = $speed / ($max_speed - $min_speed);
    my $value_angle  = $angle_min + ($angle_max - $angle_min) * $current_value;
    my $value_end_x  = $half_width - $radius * sin(deg2rad($value_angle));
    my $value_end_y  = $half_width + $radius * cos(deg2rad($value_angle));

    my $curve_bg     = sprintf('M%f %f A%d %d 0 1 1 %f %f', $start_x, $start_y, $radius, $radius, $end_x, $end_y);
    my $large_arc    = $value_angle > (180 + $dial_gap_deg/2) ? 1 : 0;
    my $curve_fg     = sprintf('M%f %f A%d %d 0 %d 1 %f %f', $start_x, $start_y, $radius, $radius, $large_arc, $value_end_x, $value_end_y);

    return <<HTML;
    <div>
        <svg width="100" height="100">
            <path d="M0 0 L0 100 L100 100 L100 0 Z" stroke="black" stroke-width="1" fill="none"/>

            <path d="${curve_bg}" stroke="#e0e0e0" stroke-width="5" fill="none" stroke-linecap="round" />
            <path d="${curve_fg}" stroke="#55aa11" stroke-width="10" fill="none" stroke-linecap="round" />
            <text x="50" y="50" fill="#55aa11" font-family="Helvetica, sans-serif" dominant-baseline="middle" text-anchor="middle" font-size="2em" font-weight="bold">${round_speed}</text>
            <text x="50" y="68" fill="#555555" font-family="Helvetica, sans-serif" dominant-baseline="middle" text-anchor="middle" font-size="0.75em" >mph</text>
        </svg>
    </div>
HTML
}

sub write_html($file_no, $data) {
    my $html_filename = sprintf('/tmp/gauges%04d.html', $file_no);
    open(my $fh, '>', $html_filename);
    binmode($fh);

    my $lat_long = gauge_lat_long($data->{lat_long});
    my $speed    = gauge_speed($data->{speed});


    print $fh <<HTML;
<!DOCTYPE html>
<html lang="en" dir="ltr">
<head>
  <meta charset="UTF-8"/>
  <title>Black Mountain Pass</title>
</head>
<body>
  <!-- LOCATION -->
$lat_long
  <!-- SPEED -->
$speed
  <!-- COURSE -->
  <div>
    <svg width="100" height="100">
      <path d="M0 0 L0 100 L100 100 L100 0 Z" stroke="black" stroke-width="1" fill="none"/>

      <circle cx="50" cy="50" r="40" stroke="#e0e0e0" stroke-width="5" fill="none" />
      <path d="M50 50 L89.9756330807638 51.3959798681" stroke="#f0f0f0" stroke-width="2"/>
      <circle cx="89.9756330807638" cy="51.3959798681" r="6" fill="#55aa11" />
      <text x="50" y="50" fill="#55aa11" font-family="Helvetica, sans-serif" dominant-baseline="middle" text-anchor="middle" font-size="1.5em" font-weight="bold">92</text>
      <text x="50" y="68" fill="#555555" font-family="Helvetica, sans-serif" dominant-baseline="middle" text-anchor="middle" font-size="0.75em" >course</text>
    </svg>
  </div>

  <!-- ELEVATION -->
  <div>
    <svg width="100" height="100">
      <path d="M0 0 L0 100 L100 100 L100 0 Z" stroke="black" stroke-width="1" fill="none"/>

      <path d="
        M10 80
        C10 70 20 90 20 80
        S30 90 30 80
        S40 90 40 80
        S50 90 50 80
        S60 90 60 80
        S70 90 70 80
        S80 90 80 80
        " stroke="#2E8B82" stroke-width="4" fill="none"/>
      <path d="
        M86 80 L94 80
        M90 80 L90 10
        M86 10 L94 10
        " stroke="#999999" stroke-width="1" fill="none"/>
      <text x="45" y="40" fill="#55aa11" font-family="Helvetica, sans-serif" dominant-baseline="middle" text-anchor="middle" font-size="1.5em" font-weight="bold">372.4</text>
      <text x="45" y="58" fill="#555555" font-family="Helvetica, sans-serif" dominant-baseline="middle" text-anchor="middle" font-size="0.75em">m a.s.l.</text>
    </svg>
  </div>

</body>
</html>
HTML

    my $image_filename = sprintf('output/image%04d.png', $file_no);
    print "Write $image_filename\n";
    system("/usr/local/bin/wkhtmltoimage --quality 100 ${html_filename} ${image_filename} &");
}