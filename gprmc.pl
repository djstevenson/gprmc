#!/usr/bin/env perl
use Mojo::Base -signatures;
use v5.44;
use utf8;

# Takes GPS data from CSV and generates HTML gauges for each frame

use FindBin::libs;
use DateTime;
use DateTime::Format::ISO8601::Format;
use Template;
use Text::CSV_XS;

use Frame;
use Frame::Location;

binmode STDIN, ':encoding(UTF-8)';

my $csv = Text::CSV_XS->new({binary => 1, auto_diag => 1, sep_char => ','});
$csv->header(*STDIN);

my $fileno = 1;

while (my $row = $csv->getline_hr(*STDIN)) {

    my $frame = Frame->new(
        direction => $row->{track},
        speed     => $row->{speed} * 0.621371, # kph to mph
        limit     => 30,
        location  => Frame::Location->new(
            latitude  => $row->{latitude},
            longitude => $row->{longitude},
            altitude  => $row->{altitude},
        ),
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
