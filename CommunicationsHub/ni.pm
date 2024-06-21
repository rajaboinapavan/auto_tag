# Version: 0.0.2
# Timestamp: 2024-06-21 19:01:16 +0530
# Author: rajaboinapavan

package MyModule; #

use strict;
use warnings;

# Constructor (optional)
sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    return $self;
}

# Method to greet a user
sub greet {
    my ($self, $name) = @_;
    return "Hello, $name!";
}

1;  # Modules must return a true value
