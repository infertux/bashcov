#!/usr/bin/env bash
# Constructs Bashcov::Scanner must group like Bash does. This script is only
# parsed, never run. Don't add a "$(" here without its ")" ;-)

single='a
b'
double="a
b \"c\"
d"
ansi=$'a\'
b'
nested="$(printf '%s
' "x")"
param="${HOME:-a
b}"
array=(
  one # comment with a quote: '
  "two
  three"
)
(( total = 1 +
  2 ))
echo $((1 << 2)) "$(( (1 + 2) * 3 ))"

cat <<EOF
heredoc with 'quotes' and "quotes"
EOF
cat <<-'EOF'
	quoted delimiter, tab-indented
	EOF
cat <<"END" | tr a-z A-Z; echo after
$not expanded
END
cat <<\EOF
escaped delimiter
EOF
x=$(cat <<EOF
heredoc in a substitution )
EOF
)
cat <<A <<B
first
A
second
B
read -r word <<< "here string"

echo one \
  two \
  three
echo one &&
  echo two
echo one \
  && echo two \
  || echo three
true | \
  cat

out=$(
  case $1 in
    a) echo "a" ;;
    (b) echo b ;;
  esac
)
out=`echo 'a
b'`

# a comment with a lone ' quote
echo it\'s # and an escaped quote
echo "it's" 'say "hi"' $$ $# "${#out}"
f() {
  echo "in
  function"
}
functions=$(cat <<\EOF
not a function declaration
EOF
)
