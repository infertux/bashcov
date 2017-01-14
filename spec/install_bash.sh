#!/bin/bash -ex

if [ "$INSTALL_BASH_VERSION" = "sh" ]; then
    echo "Uninstalling Bash, using POSIX-compliant sh"
    echo 'Yes, do as I say!' | sudo apt-get --yes --force-yes purge bash
    whereis bash
    exit
fi

if [ -z $INSTALL_BASH_VERSION ]; then
    echo "No \$INSTALL_BASH_VERSION, using default Bash"
    exit
fi

set -u

echo "Installing bash $INSTALL_BASH_VERSION..."

lftp -e 'mirror --continue --delete --parallel=10 --verbose /gnu/bash/ ; quit' ftp.gnu.org
cd bash

tar xvf bash-$INSTALL_BASH_VERSION.tar.gz
pushd bash-$INSTALL_BASH_VERSION

patches="../bash-$INSTALL_BASH_VERSION-patches/bash$(echo $INSTALL_BASH_VERSION | tr -d .)-???"
for patch in $(find .. -wholename "$patches" | sort); do
    echo "Applying $patch"
    patch -f -p0 <$patch
done

./configure --exec-prefix /
make
sudo make install

popd
rm -rf bash-$INSTALL_BASH_VERSION
