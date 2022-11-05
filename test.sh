#!/bin/bash

set -euo pipefail

jobs=$(grep -o '^[a-z].*:$' .gitlab-ci.yml | tr -d ':' | grep -Ev '^(before_script)$')

for job in $jobs; do
    echo "Running ${job}..."
    gitlab-runner exec docker "$job"
done
