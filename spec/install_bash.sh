#!/bin/bash -ex

if [ -z $BASHVER ]; then
    echo "No \$BASHVER, using default Bash"
    exit
fi

set -u

echo "Installing bash $BASHVER..."

lftp -e 'mirror --continue --delete --parallel=10 --verbose /gnu/bash/ ; quit' ftp.gnu.org
cd bash

tar xvf bash-$BASHVER.tar.gz
pushd bash-$BASHVER

patches="../bash-$BASHVER-patches/bash$(echo $BASHVER | tr -d .)-???"
for patch in $(find .. -wholename "$patches" | sort); do
    echo "Applying $patch"
    patch -f -p0 <$patch
done

./configure --exec-prefix /
make
sudo make install

popd
rm -rf bash-$BASHVER
