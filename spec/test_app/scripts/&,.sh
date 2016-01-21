#!/bin/bash

{
    declare -x ray=specs
    (echo "$ray") &
    wait
} &

wait
