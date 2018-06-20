#!/bin/bash

# to kill session :
# screen -S rh -X quit

#if [ $# -ne 3 ]
#then
#  echo "./sc.sh file partition dstpath"
#  exit
#fi

#file=$1
#partition=$2
#dstpath=$3

export RH_BIN_DIR="/usr/local/sbin"
export RH_PATH="/usr/local/sbin/rh2.sh"
export RH_DIR="/root/rh2"
export REMOTE_RH_PATH="/usr/local/sbin/receive.sh"

cat > $RH_DIR/rc <<EOL
#chdir /etc
screen 0
stuff "$RH_BIN_DIR/initrh2.sh $@\n"
split
focus down
#chdir /tmp
screen 1
#stuff "./rhlogs.sh\n"

# uncomment next three lines to get a third window (bottom right)
split -v
focus bottom
screen 2

focus top
EOL

if [ ! -d $RH_DIR ]
then
  mkdir $RH_DIR
fi

screen -S rh -c $RH_DIR/rc

#screen -S rh -X stuff blabla
