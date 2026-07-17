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
use Template;
use Text::CSV_XS;
use Readonly;

use Frame;

use DBI;

Readonly my $EARTH_RADIUS_M => 6_371_000;

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
    );
    writeHTML($fileno, $frame);
    $fileno++;
}

print "Done\n";

sub writeHTML($fileno, $frame) {
    mkdir 'output' unless -d 'output';
    my $dir_no = sprintf('%02d', int($fileno / 10_000));
    mkdir "output/$dir_no" unless -d "output/$dir_no";
    my $html_filename = sprintf('output/%s/gauges%05d.html', $dir_no, $fileno);
    open(my $fh, '>:utf8', $html_filename);

    my $tt2 = Template->new({ INCLUDE_PATH => 'templates' });
    $tt2->process('main.tt2', {frame => $frame}, $fh) or die $tt2->error();
}
