#!/bin/zsh
# Make the script return a failure code if any of the commands executed in the middle fail (even if they are piped)
# For more info, see: https://stackoverflow.com/questions/821396/aborting-a-shell-script-if-any-command-returns-a-non-zero-value
set -e
set -o pipefail

# Find SwiftLint from multiple sources (Brew, Pods, Mint)
SWIFTLINT=""

# Check Brew
if command -v swiftlint &> /dev/null; then
    SWIFTLINT="swiftlint"
    echo "Using SwiftLint from Brew"
# Check Pods
elif [ -f "Pods/SwiftLint/swiftlint" ]; then
    SWIFTLINT="Pods/SwiftLint/swiftlint"
    echo "Using SwiftLint from Pods"
# Check Mint
elif command -v mint &> /dev/null; then
    SWIFTLINT="mint run realm/SwiftLint"
    echo "Using SwiftLint from Mint"
else
    echo "Error: SwiftLint not found. Please install via Brew, Pods, or Mint."
    exit 1
fi

eval "$SWIFTLINT lint --config \".swiftlint.yml\" --strict" | sed 's/warning:/error:/g'
eval "$SWIFTLINT lint --config \".swiftlint_test.yml\" --strict" | sed 's/warning:/error:/g'
