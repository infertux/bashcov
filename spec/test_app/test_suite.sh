#!/usr/bin/env bash

echo "UID=${UID}" >&2
echo "PS4=${PS4}" >&2

cd $(dirname $0)

find scripts -type f -perm -111 -print -execdir '{}' \;
