#!/bin/bash

if
  [[ false = true ]]
then
  echo 1
elif
  [[ 2 ]]
then
  echo 2
else
  echo 3
fi

[ false = true ] || \
  [[ 42 -eq 1337 ]] || [[ 1 -eq 1 ]] \
  && true && \
  echo 'what?' || \
  echo 'no!'

variable=($(
  echo hi
))
echo after
