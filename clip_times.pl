#!/usr/bin/env perl
use Mojo::Base -signatures;
use v5.42;
use utf8;

# Takes a directory of movie files from Nextbase.  Only processes FH files (front
# facing camera).  Extracts the start/end time of the GPS data, allowing checks for
# overlaps or missing data. Outputs the results in a CSV.

# carton exec -- clip_times.pl <dir>

use FindBin::libs;
use DateTime;
use DateTime::Format::ISO8601::Format;

binmode STDIN, ':encoding(UTF-8)';

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
# I only care about the last Date/Time each time we see Track data.

my $dir_name = shift @ARGV or die "Usage: $0 <dir>\n";
die "Directory $dir_name does not exist\n" unless -d $dir_name;

my $dt_formatter = DateTime::Format::ISO8601::Format->new;

# Output frame rate: we emit one interpolated CSV row per tick.
my $frame_rate = 30;

# Two timestamps within this many seconds of each other are treated as equal,
# to absorb jitter in the GPS clock.
my $jitter_tolerance = 0.005;

# Numeric fields captured per sample and written (with the timestamp) to the CSV.
my @fields = qw(latitude longitude altitude speed track);

opendir my $dh, $dir_name or die "Cannot open directory $dir_name: $!\n";
my @files = sort grep { /^\d{6}_\d{6}_\d{3}_FH\.MP4$/ } readdir $dh;
closedir $dh;

# Per-file list of GPS samples, in the order they appear in the file. Each
# sample is a hashref: datetime, latitude, longitude, altitude, speed, track.
# Keyed by filename.
my %file_samples;

for my $filename (@files) {
    my $path = "$dir_name/$filename";
    open my $exif, '-|', 'exiftool', '-ee', '-n', $path
        or die "Cannot run exiftool on $path: $!\n";

    # Fields are emitted one per line, so we remember the most recent value of
    # each and commit a complete sample when we reach the GPS Track line (which
    # marks the end of a GPS sample).
    my $last_datetime;
    my %last;               # latitude/longitude/altitude/speed seen so far
    my @samples;            # one sample hashref per GPS Track
    my $num = qr/-?\d+(?:\.\d+)?/;
    while (my $line = <$exif>) {
        if ($line =~ /^GPS \s Date\/Time \s* : \s*
            (\d{4}):(\d\d):(\d\d) \s+ (\d\d):(\d\d):(\d\d)(\.\d+)?Z/x) {
            my ($year, $month, $day, $hour, $min, $sec, $frac) =
                ($1, $2, $3, $4, $5, $6, $7 // 0);

            # The GPS data is sampled at 10Hz, so round to the nearest 0.1s:
            # the odd off-grid timestamp (e.g. 14:44:31.109Z) is close enough,
            # and snapping it to the grid means less interpolation later.
            my $tenths = int($frac * 10 + 0.5);

            $last_datetime = DateTime->new(
                year       => $year,
                month      => $month,
                day        => $day,
                hour       => $hour,
                minute     => $min,
                second     => $sec,
                nanosecond => ($tenths % 10) * 100_000_000,
                time_zone  => 'UTC',
                formatter  => $dt_formatter,
            );
            # .95 and above rounds up into the next second.
            $last_datetime->add(seconds => 1) if $tenths == 10;
        }
        elsif ($line =~ /^GPS \s Latitude  \s* : \s* ($num)/x)  { $last{latitude}  = $1 }
        elsif ($line =~ /^GPS \s Longitude \s* : \s* ($num)/x)  { $last{longitude} = $1 }
        elsif ($line =~ /^GPS \s Altitude  \s* : \s* ($num)/x)  { $last{altitude}  = $1 }
        elsif ($line =~ /^GPS \s Speed     \s* : \s* ($num)/x)  { $last{speed}     = $1 }
        elsif ($line =~ /^GPS \s Track     \s* : \s* ($num)/x) {
            # End of a GPS sample: commit the last values we saw.
            die "GPS Track without preceding GPS Date/Time in $path\n"
                unless defined $last_datetime;
            push @samples, {
                datetime => $last_datetime,
                track    => $1,
                %last,
            };
        }
    }
    close $exif;

    die "No GPS date/time found in $path\n" unless @samples;

    $file_samples{$filename} = \@samples;
}

# Merge every file's samples into one strictly-increasing timeline. @files is
# sorted, so the timestamps are chronological. Where files overlap, the newer
# (later) file wins: we drop any already-merged samples at or after the next
# file's first timestamp before appending it.
my @merged;
for my $filename (@files) {
    my $samples = $file_samples{$filename};
    my $start   = hires_epoch($samples->[0]{datetime});
    pop @merged
        while @merged
        && hires_epoch($merged[-1]{datetime}) >= $start - $jitter_tolerance;
    push @merged, @$samples;
}

# Emit one CSV row per tick between the first and last timestamp. Where a real
# sample lands on a tick (within the jitter tolerance) we use it directly;
# otherwise we linearly interpolate between the samples bracketing the tick.
say join ',', 'timestamp', @fields;

my $first = hires_epoch($merged[0]{datetime});
my $last  = hires_epoch($merged[-1]{datetime});
my $ticks = int(($last - $first) * $frame_rate + 0.5);

my $j = 0;    # index of the merged sample at or just before the current tick
for my $tick (0 .. $ticks) {
    my $t = $first + $tick / $frame_rate;

    # Advance so $merged[$j] is the last sample at or before $t.
    $j++ while $j + 1 <= $#merged && hires_epoch($merged[$j + 1]{datetime}) <= $t;

    my $before = $merged[$j];
    my $after  = $merged[$j + 1];    # undef past the final sample
    my $bt     = hires_epoch($before->{datetime});

    my @values;
    if (abs($t - $bt) <= $jitter_tolerance) {
        @values = @{$before}{@fields};                          # real sample
    }
    elsif ($after && abs($t - hires_epoch($after->{datetime})) <= $jitter_tolerance) {
        @values = @{$after}{@fields};                           # real sample
    }
    elsif ($after) {
        my $at   = hires_epoch($after->{datetime});
        my $frac = ($t - $bt) / ($at - $bt);
        @values  = map { $before->{$_} + $frac * ($after->{$_} - $before->{$_}) } @fields;
    }
    else {
        @values = @{$before}{@fields};    # final tick, nothing to interpolate to
    }

    say join ',', datetime_from_hires($t), @values;
}

# Seconds since the epoch, including the fractional (sub-second) part.
sub hires_epoch ($dt) {
    return $dt->epoch + $dt->nanosecond / 1_000_000_000;
}

# Inverse of hires_epoch: build a formatted UTC DateTime from a fractional
# epoch, rounded to the nearest millisecond to avoid float noise in the output.
sub datetime_from_hires ($epoch) {
    my $whole = int($epoch);
    my $milli = int(($epoch - $whole) * 1_000 + 0.5);
    if ($milli >= 1_000) { $whole++; $milli -= 1_000 }
    return DateTime->from_epoch(epoch => $whole, time_zone => 'UTC')
        ->set(nanosecond => $milli * 1_000_000)
        ->set_formatter($dt_formatter);
}

