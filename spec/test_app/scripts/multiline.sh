#!/bin/bash
# nil
if # nil
  [[ false = true ]] # 1
then # nil
  echo 1 # 0
elif # nil
  [[ 2 ]] # 1
then # nil
  echo 2 # 1
else # nil
  echo 3 # 0
fi # nil
# nil
[ false = true ] || \
  [[ 42 -eq 1337 ]] || [[ 1 -eq 1 ]] \
  && true && \
  echo 'what?' || \
  echo 'no!'
# nil
# nil
variable=($( # nil
  echo hi
)) # 2
# nil
# nil
# nil
echo after1 # 1
echo after2 # 1
