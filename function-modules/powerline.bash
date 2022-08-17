PYTHON_VERSION="python$(python --version | awk '{print $NF}' | cut -d. -f1,2)"
if which powerline-daemon &>/dev/null && ! ps aux | grep -v grep | grep -q powerline-daemon; then
    export POWERLINE_BASH_CONTINUATION=1
    export POWERLINE_BASH_SELECT=1
    powerline-daemon -q
fi
<<<<<<< HEAD
source /usr/local/lib/python3.9/dist-packages/powerline/bindings/bash/powerline.sh
#source /usr/local/lib/${PYTHON_VERSION}/dist-packages/powerline/bindings/bash/powerline.sh
#source /usr/share/powerline/bindings/bash/powerline.sh
=======
# source /usr/local/lib/python3.10/dist-packages/powerline/bindings/bash/powerline.sh
source /usr/local/lib/${PYTHON_VERSION}/dist-packages/powerline/bindings/bash/powerline.sh
>>>>>>> cf2f08d (Changes made for asteroid - yet to be merged)

