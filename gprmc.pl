#!/usr/bin/env perl
use Mojo::Base -signatures;
use v5.44;
use utf8;

# Takes GPS data from CSV and generates HTML gauges for each frame

use FindBin::libs;
use DateTime;
use DateTime::Format::ISO8601;
use DateTime::Format::ISO8601::Format;
use Math::Trig qw(great_circle_distance deg2rad pip2);
use Mojo::JSON qw(decode_json);
use Template;
use Text::CSV_XS;
use Readonly;

use Frame;

use DBI;

Readonly my $EARTH_RADIUS_M => 6_371_000;

# Map render settings - change these to resize the map or how much ground it covers.
Readonly my $MAP_WIDTH_PX  => 400;
Readonly my $MAP_HEIGHT_PX => 400;
Readonly my $MAP_RADIUS_M  => 2_500; # metres shown in each direction from current position
Readonly my $MAP_SCALE     => $MAP_WIDTH_PX / (2 * $MAP_RADIUS_M); # pixels per metre

# The road/place background is expensive to fetch and, at 30fps, moves each
# frame by a sub-pixel amount that text rendering can't track smoothly. So
# instead we snapshot it and only re-fetch periodically, sliding just the
# position marker across the frozen background between snapshots.
Readonly my $MAP_RECENTRE_INTERVAL_S => 10; # re-fetch the background at least this often
Readonly my $MAP_RECENTRE_MARGIN_M   => $MAP_RADIUS_M * 0.7; # ...or sooner if we drift this far from the last snapshot

Readonly my %MAP_ROAD_CLASS => (
    motorway       => 'road-major',
    motorway_link  => 'road-major',
    trunk          => 'road-major',
    trunk_link     => 'road-major',
    primary        => 'road-major',
    primary_link   => 'road-major',
    secondary      => 'road-medium',
    secondary_link => 'road-medium',
    tertiary       => 'road-medium',
    tertiary_link  => 'road-medium',
);

Readonly my %MAP_ROAD_SIGN_STYLE => (
    motorway       => 'motorway',
    motorway_link  => 'motorway',
    trunk          => 'trunk',
    trunk_link     => 'trunk',
    primary        => 'other',
    primary_link   => 'other',
    secondary      => 'other',
    secondary_link => 'other',
    tertiary       => 'other',
    tertiary_link  => 'other',
);

Readonly my $ROAD_LABEL_FONT_SIZE => 11;

Readonly my %MAP_PLACE_FONT_SIZE => (
    city    => 22,
    town    => 16,
    village => 13,
    hamlet  => 11,
);

my $speed_limit = undef;
my $start_time = undef;
my $distance = 0;
my $prev_position = undef;

binmode STDIN, ':encoding(UTF-8)';

my $csv = Text::CSV_XS->new({binary => 1, auto_diag => 1, sep_char => ','});
$csv->header(*STDIN);

my $dbh = DBI->connect(
    'dbi:Pg:dbname=gb', undef, undef,
    { RaiseError => 1, AutoCommit => 1 },
);
Readonly my $SPEED_LIMIT_SQL => <<'SQL';
WITH position AS (
    SELECT ST_Transform(
        ST_SetSRID(ST_MakePoint(?, ?), 4326),
        27700
    ) AS geom
)
SELECT
    r.maxspeed
FROM osm_roads r
    CROSS JOIN position p
WHERE ST_DWithin(r.geom_bng, p.geom, 30)
ORDER BY r.geom_bng <-> p.geom
LIMIT 1
SQL

my $stm = $dbh->prepare($SPEED_LIMIT_SQL);

Readonly my $MAP_HIGHWAY_LIST => join ', ', map { $dbh->quote($_) } sort keys %MAP_ROAD_CLASS;

Readonly my $MAP_LINES_SQL => <<SQL;
WITH centre AS (
    SELECT ST_Transform(
        ST_SetSRID(ST_MakePoint(?, ?), 4326),
        27700
    ) AS geom
),
bbox AS (
    SELECT ST_Expand(centre.geom, ?) AS geom FROM centre
)
SELECT
    r.highway,
    r.ref,
    ST_X(centre.geom) AS centre_x,
    ST_Y(centre.geom) AS centre_y,
    ST_AsGeoJSON(ST_Intersection(r.geom_bng, bbox.geom)) AS geojson
FROM osm_roads r, bbox, centre
WHERE r.geom_bng && bbox.geom
  AND r.highway IN ($MAP_HIGHWAY_LIST)
ORDER BY r.way_id
SQL

my $map_stm = $dbh->prepare($MAP_LINES_SQL);

Readonly my $MAP_PLACES_SQL => <<'SQL';
WITH centre AS (
    SELECT ST_Transform(
        ST_SetSRID(ST_MakePoint(?, ?), 4326),
        27700
    ) AS geom
),
bbox AS (
    SELECT ST_Expand(centre.geom, ?) AS geom FROM centre
)
SELECT
    p.name,
    p.place,
    ST_X(centre.geom) AS centre_x,
    ST_Y(centre.geom) AS centre_y,
    ST_X(p.geom_bng) AS x,
    ST_Y(p.geom_bng) AS y
FROM osm_places p, bbox, centre
WHERE p.geom_bng && bbox.geom
  AND p.name IS NOT NULL
SQL

my $places_stm = $dbh->prepare($MAP_PLACES_SQL);

Readonly my $BNG_POSITION_SQL => <<'SQL';
SELECT ST_X(t.geom) AS x, ST_Y(t.geom) AS y
FROM (SELECT ST_Transform(ST_SetSRID(ST_MakePoint(?, ?), 4326), 27700) AS geom) t
SQL

my $bng_stm = $dbh->prepare($BNG_POSITION_SQL);

my $fileno = 1;

# Background snapshot state: the BNG position it was fetched at, when, and
# the cached (already pixel-transformed) lines/labels/places themselves.
my ($map_anchor_x, $map_anchor_y, $map_anchor_time);
my ($cached_map_lines, $cached_map_road_labels, $cached_map_places) = ([], [], []);

while (my $row = $csv->getline_hr(*STDIN)) {

    $stm->execute($row->{longitude}, $row->{latitude});
    my ($new_maxspeed) = $stm->fetchrow_array;
    if (defined $new_maxspeed) {
        if ($new_maxspeed =~ m{\A(\d+) mph\Z} ) {
            $speed_limit = $1;
        }
        else {
            print "Unknown limit: $new_maxspeed\n";
        }
    }

    my $frame_time = DateTime::Format::ISO8601->parse_datetime($row->{timestamp}) or die;

    $bng_stm->execute($row->{longitude}, $row->{latitude});
    my ($bng_x, $bng_y) = $bng_stm->fetchrow_array;

    my $need_recentre = !defined $map_anchor_time;
    if (!$need_recentre) {
        my $elapsed = $frame_time->epoch - $map_anchor_time->epoch;
        my $drift = sqrt(($bng_x - $map_anchor_x)**2 + ($bng_y - $map_anchor_y)**2);
        $need_recentre = 1 if $elapsed >= $MAP_RECENTRE_INTERVAL_S || $drift >= $MAP_RECENTRE_MARGIN_M;
    }
    if ($need_recentre) {
        ($cached_map_lines, $cached_map_road_labels) = fetch_map_lines($map_stm, $row->{longitude}, $row->{latitude});
        $cached_map_places = fetch_map_places($places_stm, $row->{longitude}, $row->{latitude});
        ($map_anchor_x, $map_anchor_y) = ($bng_x, $bng_y);
        $map_anchor_time = $frame_time;
    }
    my ($marker_x, $marker_y) = bng_to_pixel($bng_x, $bng_y, $map_anchor_x, $map_anchor_y);

    my $position = [deg2rad($row->{longitude}), pip2 - deg2rad($row->{latitude})];
    if (defined $prev_position) {
        $distance += great_circle_distance(@$prev_position, @$position, $EARTH_RADIUS_M);
    }
    $prev_position = $position;

    my $rounded_time = $frame_time->clone->set_nanosecond(0);
    $start_time = $rounded_time unless defined $start_time;
    my $dd = $frame_time->subtract_datetime($start_time);
    my $frame = Frame->new(
        timestamp => $frame_time,
        reltime   => $frame_time->subtract_datetime($start_time->clone->set_nanosecond(0)),
        direction => $row->{track},
        speed     => $row->{speed} * 0.621371, # kph to mph
        limit     => 30,
        latitude    => $row->{latitude},
        longitude   => $row->{longitude},
        altitude    => $row->{altitude},
        speed_limit => $speed_limit,
        distance  => $distance,
        map_width  => $MAP_WIDTH_PX,
        map_height => $MAP_HEIGHT_PX,
        map_lines  => $cached_map_lines,
        map_road_labels => $cached_map_road_labels,
        map_places => $cached_map_places,
        marker_x   => $marker_x,
        marker_y   => $marker_y,
    );
    writeHTML($fileno, $frame);
    $fileno++;
}

print "Done\n";

sub bng_to_pixel($x, $y, $anchor_x, $anchor_y) {
    return (
        ($x - $anchor_x) * $MAP_SCALE + $MAP_WIDTH_PX / 2,
        $MAP_HEIGHT_PX / 2 - ($y - $anchor_y) * $MAP_SCALE,
    );
}

sub fetch_map_lines($map_stm, $longitude, $latitude) {
    $map_stm->execute($longitude, $latitude, $MAP_RADIUS_M);

    my @lines;
    my @road_labels;
    my %seen_ref;
    while (my $row = $map_stm->fetchrow_hashref) {
        my $geom = decode_json($row->{geojson});
        my @parts = $geom->{type} eq 'MultiLineString' ? @{$geom->{coordinates}}
                  : $geom->{type} eq 'LineString'      ? ($geom->{coordinates})
                  :                                       ();
        my $road_class = $MAP_ROAD_CLASS{$row->{highway}};

        for my $part (@parts) {
            next if @$part < 2;
            my @pixels = map {
                my ($x, $y) = @$_;
                [ bng_to_pixel($x, $y, $row->{centre_x}, $row->{centre_y}) ];
            } @$part;
            push @lines, {
                class  => $road_class,
                points => join(' ', map { sprintf('%.1f,%.1f', @$_) } @pixels),
            };

            my $sign_style = $MAP_ROAD_SIGN_STYLE{$row->{highway}};
            if (defined $sign_style && defined $row->{ref} && length $row->{ref}
                    && !$seen_ref{$row->{ref}}++) {
                my ($x, $y) = @{ $pixels[int(@pixels / 2)] };
                push @road_labels, {
                    style  => $sign_style,
                    text   => $row->{ref},
                    x      => $x,
                    y      => $y,
                    width  => length($row->{ref}) * $ROAD_LABEL_FONT_SIZE * 0.62 + 6,
                    height => $ROAD_LABEL_FONT_SIZE + 4,
                    font_size => $ROAD_LABEL_FONT_SIZE,
                };
            }
        }
    }

    return (\@lines, \@road_labels);
}

sub fetch_map_places($places_stm, $longitude, $latitude) {
    $places_stm->execute($longitude, $latitude, $MAP_RADIUS_M);

    my @places;
    while (my $row = $places_stm->fetchrow_hashref) {
        my ($x, $y) = bng_to_pixel($row->{x}, $row->{y}, $row->{centre_x}, $row->{centre_y});
        push @places, {
            name      => $row->{name},
            font_size => $MAP_PLACE_FONT_SIZE{$row->{place}} // 11,
            x         => $x,
            y         => $y,
        };
    }

    return \@places;
}

sub writeHTML($fileno, $frame) {
    mkdir 'output' unless -d 'output';
    my $dir_no = sprintf('%02d', int($fileno / 1_000));
    mkdir "output/$dir_no" unless -d "output/$dir_no";
    my $html_filename = sprintf('output/%s/gauges%05d.html', $dir_no, $fileno);
    open(my $fh, '>:utf8', $html_filename);

    my $tt2 = Template->new({ INCLUDE_PATH => 'templates' });
    $tt2->process('main.tt2', {frame => $frame}, $fh) or die $tt2->error();
}
