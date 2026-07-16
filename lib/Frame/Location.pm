package Frame::Location;
use Moose;
use namespace::autoclean;
use DBI;

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


__PACKAGE__->meta->make_immutable;
1;
