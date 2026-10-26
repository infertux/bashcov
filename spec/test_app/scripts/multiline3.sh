#!/usr/bin/env bash

echo 1 \
     2 \
     3 \
     4
echo \
  'a
b'
FOO=\
"x
y"
readonly BAR=\
'
'
A='x
y'; B='p
q'
echo "a
b" && echo "c
d"
echo "say
\"hi\"
there"
msg="path\\
c:\\dir"
x='a\'
echo "it's" "multi
line"
cat <<EOF
one
EOF
if false; then
  echo "EOF"
fi
cat <<EOF
two
EOF
cat <<EOF
	EOF
EOF
cat <<-EOF
	three
	EOF
cat <<"EOF"
four
EOF
cat <<\EOF
five
EOF
