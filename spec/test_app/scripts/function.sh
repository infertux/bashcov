#!/bin/bash

function f1 {
    echo f1
}

f2() {
    f1
    echo f2
}

__a_bc()
{
    echo __a_bc
}

f1
f2
__a_bc

