#!/bin/bash
cd ../
cp -R bashprofile /home/$(whoami)/.profile

mv /home/$(whoami)/.bash_profile /home/$(whoami)/.bash_profile_$(date +%Y-%m-%d);
cp bashprofile/.bash_profile /home/$(whoami)/.bash_profile

if [ ! -f /home/$(whoami)/.gitconfig) ] ; then
    cp bashprofile/.gitconfig /home/$(whoami)/.gitconfig)
fi

# load the new bash profile
source /home/$(whoami)/.bash_profile