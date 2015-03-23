#!/bin/bash

function command_substitution {
    echo
}

function prints_to_stderr {
    >&2 echo "data"
}

prints_to_stderr 2> >(command_substitution)
