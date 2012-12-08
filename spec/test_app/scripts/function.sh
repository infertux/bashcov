#!/bin/bash

function f1 {
    echo f1
}

f2() {
    f1
    echo f2
}

f1
f2

