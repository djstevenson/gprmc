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
Readonly my $MAP_RADIUS_M  => 1_000; # metres shown in each direction from current position
Readonly my $MAP_SCALE     => $MAP_WIDTH_PX / (2 * $MAP_RADIUS_M); # pixels per metre

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

Readonly my $MAP_LINES_SQL => <<'SQL';
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

my $fileno = 1;

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

    my $map_lines = fetch_map_lines($map_stm, $row->{longitude}, $row->{latitude});
    my $map_places = fetch_map_places($places_stm, $row->{longitude}, $row->{latitude});

    my $position = [deg2rad($row->{longitude}), pip2 - deg2rad($row->{latitude})];
    if (defined $prev_position) {
        $distance += great_circle_distance(@$prev_position, @$position, $EARTH_RADIUS_M);
    }
    $prev_position = $position;

    my $frame_time = DateTime::Format::ISO8601->parse_datetime($row->{timestamp}) or die;
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
        map_lines  => $map_lines,
        map_places => $map_places,
    );
    writeHTML($fileno, $frame);
    $fileno++;
}

print "Done\n";

sub fetch_map_lines($map_stm, $longitude, $latitude) {
    $map_stm->execute($longitude, $latitude, $MAP_RADIUS_M);

    my @lines;
    while (my $row = $map_stm->fetchrow_hashref) {
        my $geom = decode_json($row->{geojson});
        my @parts = $geom->{type} eq 'MultiLineString' ? @{$geom->{coordinates}}
                  : $geom->{type} eq 'LineString'      ? ($geom->{coordinates})
                  :                                       ();

        for my $part (@parts) {
            next if @$part < 2;
            my $points = join ' ', map {
                my ($x, $y) = @$_;
                sprintf('%.1f,%.1f',
                    ($x - $row->{centre_x}) * $MAP_SCALE + $MAP_WIDTH_PX / 2,
                    $MAP_HEIGHT_PX / 2 - ($y - $row->{centre_y}) * $MAP_SCALE,
                );
            } @$part;
            push @lines, {
                class  => $MAP_ROAD_CLASS{$row->{highway}} // 'road-minor',
                points => $points,
            };
        }
    }

    return \@lines;
}

sub fetch_map_places($places_stm, $longitude, $latitude) {
    $places_stm->execute($longitude, $latitude, $MAP_RADIUS_M);

    my @places;
    while (my $row = $places_stm->fetchrow_hashref) {
        push @places, {
            name      => $row->{name},
            font_size => $MAP_PLACE_FONT_SIZE{$row->{place}} // 11,
            x         => ($row->{x} - $row->{centre_x}) * $MAP_SCALE + $MAP_WIDTH_PX / 2,
            y         => $MAP_HEIGHT_PX / 2 - ($row->{y} - $row->{centre_y}) * $MAP_SCALE,
        };
    }

    return \@places;
}

sub writeHTML($fileno, $frame) {
    mkdir 'output' unless -d 'output';
    my $dir_no = sprintf('%02d', int($fileno / 10_000));
    mkdir "output/$dir_no" unless -d "output/$dir_no";
    my $html_filename = sprintf('output/%s/gauges%05d.html', $dir_no, $fileno);
    open(my $fh, '>:utf8', $html_filename);

    my $tt2 = Template->new({ INCLUDE_PATH => 'templates' });
    $tt2->process('main.tt2', {frame => $frame}, $fh) or die $tt2->error();
}
