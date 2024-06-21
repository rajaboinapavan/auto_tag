package MyModule;

use strict;
use warnings;

# Constructor method #
sub new {
    my ($class, %args) = @_;
    my $self = bless {
        name => $args{name} || 'Anonymous',
    }, $class;
    return $self;
}

# Method to greet
sub greet {
    my ($self) = @_;
    return "Hello, my name is $self->{name}!";
}

# Method to set name
sub set_name {
    my ($self, $name) = @_;
    $self->{name} = $name;
}

# Method to get name
sub get_name {
    my ($self) = @_;
    return $self->{name};
}

1; # Ensure the module returns true value at the end
