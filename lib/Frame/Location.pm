package Frame::Location;
use Moose;
use namespace::autoclean;

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

__PACKAGE__->meta->make_immutable;
1;
