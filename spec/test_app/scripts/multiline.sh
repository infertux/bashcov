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
variable=($(echo hi)) # 2
# nil
# nil
echo "after 1" \
  "after 2" \
  "after 3" \
  "after 4"
# nil
cat <<EOF
this is
        a cat!
  actually it's a $SHELL
EOF
# nil
echo '
hello
there
'
# nil
echo the end # 1
