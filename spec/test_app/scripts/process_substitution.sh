#!/usr/bin/env bash

function print_to_stderr {
    echo "data" >&2
}

print_to_stderr 2> >(cat)

diff <(ls -l | head -n-1) <(ls -l)
