#!/bin/sh
# get png and jpg files in commit
images=$(git diff --exit-code --cached --name-only --diff-filter=ACM -- '*.png' '*.jpg' '*.jpeg')

# optimize images through imageoptim tool
# install: brew install imageoptim-cli
$(exit $?) || (imageoptim $(echo "$images" | tr '\n' ' ') && git add $images)

