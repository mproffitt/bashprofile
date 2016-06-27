#!/bin/bash
[ "$(basename $(pwd))" = 'install' ] && cd ..

source $(pwd)/function-modules/common-functions.bash

function install_profile()
{
    if [ -d ${HOME}/.bashprofile ] ; then
        warn "Skipping installation of .bashprofile - already installed"
        return 2
    fi
    inform "Installing bash profile"
    local parent=$(dirname $(pwd))
    local modulename=$(basename $(pwd))
    cd ~

    mv $parent/$modulename /home/$(whoami)/.bashprofile

    mv /home/$(whoami)/.bash_profile /home/$(whoami)/.bash_profile_$(date +%Y-%m-%d);
    cp .bashprofile/.bash_profile /home/$(whoami)/.bash_profile
}

function install_git_config()
{
    if [ ! -f /home/$(whoami)/.gitconfig ] ; then
        inform "Installing git config"
        cp .bashprofile/.gitconfig /home/$(whoami)/.gitconfig
    fi
}

function install_pip()
{
    inform "Installing pip"
    # update certs
    curl -k http://curl.haxx.se/ca/cacert.pem > /etc/pki/tls/certs/ca-bundle.crt

    python=$(which python | sed 's/\\/\\\\/')
    if [ $? -eq 0 ] && echo $(cygpath $python) | grep cygdrive; then
        error "Required cygwin python but Windows python found in path"
        error "Please check your path before continuing"
        exit 1
    fi
    # install python and easy_install
    apt-cyg install python python-setuptools

    # install pip
    easy_install-2.7 pip
}

function install_powerline()
{
    cwd=$(pwd)
    cd /tmp
    git clone https://github.com/powerline/powerline
    cd powerline
    python setup.py install

    cd /usr/lib/python2.7/site-packages/
    ln -s $(ls | grep powerline_status.*.egg)/powerline powerline

    [ ! -d ${HOME}/.local ] && mkdir ${HOME}/.local
    cd ${HOME}/.local
    mkdir bin
    mkdir -p lib/python2.7
    cp /usr/bin/powerline* bin/ # <-- this is horrible

    ln -s /usr/lib/python2.7/site-packages/powerline lib/python2.7/site-packages/

    mkdir -p ${HOME}/.config
    mv ${HOME}/.bashprofile/powerline/theme ${HOME}/.config/powerline

    cd /tmp && rm -rf powerline
    cd $cwd
}

function install_powerline_adaptor()
{
    ! which powerline &>/dev/null && install_powerline
    ! which pip &>/dev/null && install_pip
    pip install powerline-gitstatus
}


function install_bashprofile ()
{
    install_profile
    install_git_config
    #[ "$(uname -o)" = 'Cygwin' ] &&    install_powerline_adaptor
}

install_bashprofile
source /home/$(whoami)/.bash_profile

cat << EOF
A new bash profile has been installed.

If you elected to install powerline as part of this build
you will now need to install the relevant fonts.

If you are running Linux, this will have been done for you.
If however, you are running under Cygwin, this cannot be done
automatically.

instead, please install the ttf font file found at $HOME/.bashprofile/powerline/fonts
then set this as your terminal font.

Without installing this file, your powerline configuration may appear corrupt.

EOF
