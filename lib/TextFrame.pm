package TextFrame;
use Moose;
use namespace::autoclean;

has text => (
    is          => 'ro',
    isa         => 'Str',
    required    => 1,
);

has scroll_pos => (
    is          => 'ro',
    isa         => 'Num',
    required    => 1,
);

has height => (
    is          => 'ro',
    isa         => 'Int',
    required    => 1,
);

__PACKAGE__->meta->make_immutable;
1;
