#!/usr/bin/env bash

function f1 {
    echo f1 # 2
}

f2() {
    f1 # 1
    echo f2 # 1
}

__a-bc()
{
    echo __a-bc # 1
}

put-team-key() {
  echo put-team-key # 0
}

abc::def() {
    echo "${FUNCNAME[0]}" # 1
}

f1 # 1
f2 # 1
__a-bc # 1
abc::def # 1
