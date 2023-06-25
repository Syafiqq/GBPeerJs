#!/bin/zsh
# Make the script return a failure code if any of the commands executed in the middle fail (even if they are piped)
# For more info, see: https://stackoverflow.com/questions/821396/aborting-a-shell-script-if-any-command-returns-a-non-zero-value
set -e
set -o pipefail

Pods/SwiftLint/swiftlint lint --config ".swiftlint.yml" --strict | sed 's/warning:/error:/g'
Pods/SwiftLint/swiftlint lint --config ".swiftlint_test.yml" --strict | sed 's/warning:/error:/g'
