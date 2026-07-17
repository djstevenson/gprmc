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

has latitude => (
    is          => 'ro',
    isa         => 'Num',
    required    => 1,
);

has longitude => (
    is          => 'ro',
    isa         => 'Num',
    required    => 1,
);

has altitude => (
    is          => 'ro',
    isa         => 'Num',
    required    => 1,
);

has speed_limit => (
    is          => 'ro',
    isa         => 'Maybe[Int]',
    required    => 1,
);

has distance => (
    is          => 'ro',
    isa         => 'Num',
    required    => 1,
);

has distance_metres => (
    is          => 'ro',
    isa         => 'Num',
    lazy        => 1,
    default     => sub { return shift->distance; },
);

has distance_miles => (
    is          => 'ro',
    isa         => 'Num',
    lazy        => 1,
    default     => sub { return shift->distance / 1609.344; },
);

sub reltime_as_text {
    my ($self) = @_;

    my $d = $self->reltime;

    return sprintf('%02d:%02d:%02d', $d->hours, $d->minutes, $d->seconds);
}

__PACKAGE__->meta->make_immutable;
1;
