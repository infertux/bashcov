#!/bin/bash

[ false = true ] || \
  [[ 42 -eq 1337 ]] || [[ 1 -eq 1 ]] \
  && true && \
  echo 'what?' || \
  echo 'no!'

variable=($(
  echo hi
))
echo after
