#!/usr/bin/perl
use strict;
use warnings;

# Function to stage a file using Git
sub stage_file {
    my $file = shift;

    # Check if file exists
    unless (-e $file) {
        die "Error: File '$file' does not exist.\n";
    }

    # Stage the file using Git
    my $git_add_command = "git add $file";
    system($git_add_command) == 0 or die "Error: Failed to stage file '$file'. Git command returned non-zero exit status.\n";

    print "File '$file' successfully staged.\n";
}

# Main execution
if (@ARGV != 1) {
    die "Usage: perl stage_file.pl <filename>\n";
}

my $file_to_stage = $ARGV[0];
stage_file($file_to_stage);
