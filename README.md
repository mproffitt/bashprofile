# Martins BASH Profile

This repo contains the functionality for my bash profile

## Installation
To install this repo, first, clone it to your local environment. The profile needs to sit in your home folder in a
hidden folder called .bashprofile

    git clone git@github.com:mproffitt/bashprofile.git ~/.bashprofile

### Initialisation method 1

    cp ~/.bashprofile/.bash_profile ~/

### Initialisation method 2

    echo "source .bashprofile/.bash_profile" >> ~/,bash_profile

## About
Every developer on Linux has a bash profle. Whether you use it or not, one exists. Most my contain minor tweaks to the
shell, such as changing colours or adding aliases, whilst some, such as this one provide workflow functionality designed
to aid in daily duties.

My profile contains all the functions I write over time. It's likely to grow as I decide I need more shortcuts, or my
workflow changes or I write a new cool piece of functionality.

All functions and aliases in this profile can be printed out by typing ```functions``` or aliases ```respectively```.

Predominantly, this profile contains two key pieces of functionality.

### goto
The goto command is basically ```cd``` on steroids. It works by symlinking any location to ```~/.config/goto``` and then
changing to that location.

If you try and ```goto``` a location that has not previously been visited, it will ask you how to find it.

#### Example

    $ goto etc
    [INFO] etc has not been linked before
    [INFO] do you wish to locate it? [a]utomatic, [m]anual [a m] > a
    [INFO] From [r]oot, [c]urrent dir or [h]ome [r c h] > r
    [INFO] found path '/etc'
    [INFO] is this correct? >  [y n] > y
    [INFO] Linking etc in /home/mproffitt/.config/goto
    meteor : /etc: 265 entries, 2 hidden.
    $

If the location you are jumping to is a git directory, it will try and update branches against the remote defined at
```origin```:

    * Current branch
    * master from origin/master
    * develop from origin/develop

Once complete, it will then try and do the following:

    * If you are on develop, it will try and rebase or merge against master (asking which you require)
    * If your branch name starts with 'feature/' It will rebase against develop
    * if your branch name starts with `hotfix` or `release` it will rebase against master.

If the location you are jumping to contains a .sshfs.config file, it will try and mount a remote filesystem using sshfs.

The sshfs.config file should, in this instance contain the address of the server followed by the path you wish to mount
from.

#### Example

    127.0.0.1:/home/mproffitt

### Process management
This profile contains a process manager bringing multi-processing to the shell.

#### Functions:

* ```queue``` Add a command to the queue
* ```process``` Trigger the process manager
* ```restart_queue``` Restart the queue
* ```reset_queue``` Clears the current queue
* ```print_queue``` Prints the current queue as "ID - STATUS: COMMAND"

When adding functionality to the queue, one or more options may be provided:

* block=true - Block the queue until this process completes
* wait=<id1,id2> -Wait for these processes to finish before triggering this process
* push=true - push this item on the top of the queue instead of appending it to the bottom.
* -LF <filename> - A logfile to write this commands output to.

By default, this queue manager will run the queue in the background and write status updates to a simple python/curses
front end. For this, you will need python3 and the curses module.

If you do not wish to use the GUI, when triggering the process function, use -fg as its sole argument.

When the GUI is used, it works by backgrounding the entire process in a subshell.  This means that the queue remains
undisturbed in the current shell and may be triggered time and again by just calling 'process' without needing to
restart in between.

A test function is provided on the queue module. This can be triggered with ```test_queuei```.

