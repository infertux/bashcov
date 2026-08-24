#!/usr/bin/env bash

set -euo pipefail

echo "UID=${UID}" >&2
echo "PS4=${PS4}" >&2

cd $(dirname $0)

while IFS= read -r -d '' script; do
  if ! "${script}" > /dev/null ; then
    echo "WARNING: ${script} exited with non-zero."
  fi
done < <(find scripts -type f -perm -111 -print0)
