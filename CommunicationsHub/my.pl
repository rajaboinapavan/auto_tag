# Version: 0.0.1
# Timestamp: 2024-06-21 18:57:22 +0530
# Author: rajaboinapavan

#!/usr/bin/perl

use strict;
use warnings;

# Prompt for user's name
print "Please enter your name: ";
my $name = <STDIN>;  # Read input from user
chomp $name;         # Remove newline character from input

# Greet the user
print "Hello, $name! Nice to meet you.\n";
