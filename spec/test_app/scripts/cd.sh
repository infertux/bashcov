#!/usr/bin/env bash

: "${this:=that}"
: "${that:=thing}" && touch /dev/fd/1

dir="$(cd "${BASH_SOURCE%/*}" || : ; pwd -P)"
todir=''
printf -v todir -- '%s' "$(find "$dir" -type d | head -n 1)"

(cd ../.. || : ; cd "$OLDPWD" || :)


cd ../.. || :

it () { : ; }

{ for _ in {1..3}; do it; done ; } || unset -f it

cd "${todir}" || :

&>/dev/null md5sum < "$BASH_SOURCE"
