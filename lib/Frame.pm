package Frame;
use Moose;
use namespace::autoclean;

use DateTime;
use DateTime::Duration;

has timestamp => (
    is          => 'ro',
    isa         => 'DateTime',
    required    => 1,
);

has reltime => (
    is          => 'ro',
    isa         => 'DateTime::Duration',
    required    => 1,
);

has direction => (
    is          => 'ro',
    isa         => 'Num',
    required    => 1,
);

has limit => (
    is          => 'ro',
    isa         => 'Int',
    required    => 1,
);

has speed => (
    is          => 'ro',
    isa         => 'Num',
    required    => 1,
);

has location => (
    is          => 'ro',
    isa         => 'Frame::Location',
    required    => 1,
);

sub reltime_as_text {
    my ($self) = @_;

    my $d = $self->reltime;

    return sprintf('%02d:%02d:%02d', $d->hours, $d->minutes, $d->seconds);
}

__PACKAGE__->meta->make_immutable;
1;
