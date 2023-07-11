#!/usr/bin/env bash

function switch() {
    case $1 in
    -h|--help)
        echo help
        ;;
    -v|--version)
        echo version;;
    *) echo "what?";;
    esac
}

switch -h
switch bug

