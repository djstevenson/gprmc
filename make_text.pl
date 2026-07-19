#!/usr/bin/env perl
use Mojo::Base -signatures;
use v5.44;
use utf8;

use FindBin::libs;
use File::Path qw(make_path);
use IPC::Open2;
use TextFrame;
use Template;

use constant VIEWPORT_WIDTH => 1920;

use Text::CSV_XS;

my $csv = Text::CSV_XS->new({binary => 1, auto_diag => 1, sep_char => ','});
$csv->header(*STDIN);

while (my $item = $csv->getline_hr(*STDIN)) {
    my $name = $item->{name};
    my $item_dir = sprintf('./frames/text/%s', $name);
    make_path($item_dir);

    my $text_width = measure_text_width($item->{text});
    my $pos = 0;

    # "Fade in" panel (it's not a fade, it just grows in height from zero)
    for my $i (1 .. 42) {
        writeHTML($item_dir, $i, $pos, 0, '');
        $pos++;
    }
    for ( my $offset = VIEWPORT_WIDTH; $offset > -$text_width; $offset -= $item->{speed} ) {
        writeHTML($item_dir, 42, $pos, $offset, $item->{text});
        $pos++;
    }
    # Fade out
    for my $i (1 .. 42) {
        writeHTML($item_dir, 42-$i, $pos, 0, '');
        $pos++;
    }
}

# Shells out to a headless browser (measure_text_width.js) to get the exact
# rendered width for the font-family/size used in scroller.tt2, since Perl
# has no access to real font metrics for those fonts.
sub measure_text_width {
    my ($text) = @_;

    my $pid = open2(my $out, my $in, 'node', 'measure_text_width.js');
    binmode($in, ':utf8');
    print $in $text;
    close($in);
    my $width = <$out>;
    close($out);
    waitpid($pid, 0);

    chomp $width;

    # Plus arbitrary fudge factor...
    return $width + 16;
}

sub writeHTML {
    my ($dir, $height, $pos, $offset, $text) = @_;

    my $html_filename = sprintf('%s/frame_%06x.html', $dir, $pos);
    open(my $fh, '>:utf8', $html_filename);

    my $text_frame = TextFrame->new({
        scroll_pos => $offset,
        text       => $text,
        height     => $height,
    });
    my $tt2 = Template->new({ INCLUDE_PATH => 'templates' });
    $tt2->process('scroller.tt2', {frame => $text_frame}, $fh) or die $tt2->error();
}
