package MyModule;

use strict;
use warnings;

# Constructor method
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

__END__

=head1 NAME

MyModule - Example Perl Module

=head1 SYNOPSIS

  use MyModule;

  my $obj = MyModule->new(name => 'Alice');
  print $obj->greet(), "\n";       # Output: Hello, my name is Alice!
  $obj->set_name('Bob');
  print $obj->greet(), "\n";       # Output: Hello, my name is Bob!

=head1 DESCRIPTION

MyModule is a simple Perl module demonstrating basic object-oriented programming concepts.

=head1 METHODS

=head2 new(%args)

Constructor method to create a new MyModule object. Accepts an optional 'name' parameter.

=head2 greet()

Returns a greeting message using the current object's name attribute.

=head2 set_name($name)

Sets the name attribute of the object.

=head2 get_name()

Returns the current name attribute of the object.

=head1 AUTHOR

Your Name

=cut

