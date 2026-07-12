package Frame;
use Moose;
use namespace::autoclean;

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

has gradient => (
    is          => 'ro',
    isa         => 'Num',
    required    => 0,
);

__PACKAGE__->meta->make_immutable;
1;
