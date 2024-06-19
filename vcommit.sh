#!/bin/bash

# Execute the git commit command with all arguments
git commit "$@"

# Capture the exit status of the git commit command
exit_status=$?

# Exit with the same status as the git commit command
exit $exit_status
