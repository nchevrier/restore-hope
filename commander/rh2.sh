#!/bin/bash

function usage
{
  echo "$RH_PATH list"
  echo "$RH_PATH cancel"
  echo "$RH_PATH status"
  echo "$RH_PATH history"
  echo "$RH_PATH ping"
  echo "$RH_PATH send system file dst"
  echo "$RH_PATH exec system cmd"
  echo "$RH_PATH restore system"
  echo "$RH_PATH save system"
  echo "$RH_PATH script system script.sh"
  exit 1
}

# XXX
export SSH_CLIENT=""

####
# Text colors
####
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# At least one parameter
if [ $# -lt 1 ]
then
   usage
fi

declare -A argcount=([send]=4 [exec]=3 [restore]=2 [save]=2 [script]=3
  [list]=1 [cancel]=1 [history]=1 [status]=1 [ping]=1)

# first arg must be one of the RH commands
c=${argcount[$1]}
if [ ! ${argcount[$1]+_} ]
then
  usage
fi

# number of args must correspond to the number expected by the command
if [ $c -ne $# ]
then
  usage
fi

cmd=$1
cmdline=$@

####
# First, management commands
####

if [ $cmd == "list" ]
then
  cat /etc/restore/base_restore.conf | grep -v '^$'
  exit
fi

if [ $cmd == "history" ]
then
  cat $RH_DIR/history
  exit
fi

if [ $cmd == "status" ]
then
  if [ ! -f $RH_DIR/current_cmd ]
  #if [ ! -f $RH_DIR/nohup.log ]
  then
    echo "Nothing is currently running"
    exit
  fi

  echo "Local puppet log:"
  echo "----------------"
  cat $RH_DIR/nohup.log

  sample=$(ls $RH_DIR/puppets/ | grep -v nohup | head -n 1)

  echo "Sample puppet log ($sample):"
  echo "-----------------"
  ssh -q $sample "cat $RH_DIR/nohup.log"

  exit
fi

if [ $cmd == "ping" ]
then
  $0 exec rh "echo toto > /dev/null"

  if [ $? -ne 0 ]
  then
    echo "Some puppets are unreachable."
    echo "If you are waiting for reports, they might never show up."
  fi

  exit
fi

####
# Next, commands that will modify puppets configuration
####

if [ $cmd == "script" ]
then
  $0 send $system $3 /tmp
  $0 exec $system "chmod +x /tmp/$3"
  $0 exec $system "/tmp/$3"
  exit
fi

if [ $cmd != "cancel" ]
then
  system=$2

  # Find the partition (/dev/sd..) that has to be mounted
  if [ $system == "rh" ]
  then
    # No need to mount (local system is already mounted)
    partition="rh"
    touch $RH_DIR/rh.restore
  else
    line=$(grep "^$system:" /etc/restore/base_restore.conf)

    if [ $? -ne 0 ]
    then
      echo "System $system does not exist"
      exit 1
    fi

    partition=$(echo $line | cut -d ':' -f 3)
  fi
fi

shift 2

if [ $cmd == "send" ]
then
  filepath=$1
  basename=$(basename $filepath)
  rp=$(realpath $filepath)
  dirname=$(dirname $rp)

  # remove trailing slash for future comparison with source dir
  dstpath=${2%/}

  # will happen only in in RH copy
  if [ $dirname == $dstpath ]
  then
    echo -e "${RED}Cannot copy in the same directory.${NC}"
    exit
  fi
fi

# Delete any puppet reports
rm $RH_DIR/puppets/*.nohup 2> /dev/null

#screen -S rh -p 1 -X stuff '\n'

#screen -S rh -p 1 -X stuff "./ssh.sh $filepath $partition $dstpath\n"

# Force a restore before touching the system
if [ $cmd != "restore" -a $cmd != "save" -a $cmd != "cancel" ]
then
  if [ ! -f $RH_DIR/$system.restore ]
  then
    echo "Restore partition $system before touching it!"
    echo "Run \"touch $RH_DIR/$system.restore\" to mark the partition as restored."
    echo -e "${RED}Use with caution.${NC}"
    exit 1
  fi
fi

#clientip=$(cat /var/lib/dhcp/dhcpd.leases | grep '^lease ' | cut -d ' ' -f 2 | sort | uniq)

# Count puppets
clientip=$(ls $RH_DIR/puppets)
count=$(echo $clientip | wc -w)
#echo $count puppets

# start on local machine also
#clientip="$clientip 127.0.0.1"
#nohup ./receive.sh $partition $dstpath $file > nohup.log 2>&1 &

if [ $cmd == "send" ]
then
  netif=$(ip route | grep default | awk '{print $5}')
  commandline="tar cf - -C $dirname $basename | udp-sender --interface $netif --nokbd --min-receivers $count"
  screen -S rh -p 1 -X stuff "$commandline\n"

  args_remote="$dstpath"
  args_local="$dstpath $filepath"
else
  args_remote="$@"
  args_local=$args_remote
fi

####
# Exec command on puppets
####
echo "Starting command on each puppet"

for c in $clientip
do
  # Can remove next two lines in prod
  #echo -e "${RED}Remove next two lines of code${NC}"
  #scp -q $REMOTE_RH_PATH $c:$REMOTE_RH_PATH > /dev/null
  #ssh -q $c "chmod +x $REMOTE_RH_PATH"

  ssh -q $c "nohup $REMOTE_RH_PATH $cmd $partition \"$args_remote\" > $RH_DIR/nohup.log 2>&1 &" 2> /dev/null

  # Something went wrong (probably a network issue)
  if [ $? -ne 0 ]
  then
    echo -e "${RED}SSH error with puppet $c${NC}."
    echo "You should cancel the command on all puppets before you start it again."
    exit 1
  fi
done

####
# Exec command on master AFTER puppets (to let a chance to the master
# to finish its duty (eg reboot or shutdown everybody)
####
if [ $cmd == "restore" ]
then
  if [ -f $RH_DIR/$system.restore ]
  then
    rm $RH_DIR/$system.restore
  fi
fi

if [ $cmd == "exec" ]
then
  nohup $REMOTE_RH_PATH $cmd $partition "$args_local" > $RH_DIR/nohup.log 2>&1 &
else
  nohup $REMOTE_RH_PATH $cmd $partition $args_local > $RH_DIR/nohup.log 2>&1 &
fi

# Monitor nohup.log in bottom left window
if [ $cmd != "send" ]
then
  screen -S rh -p 1 -X stuff "tail -f $RH_DIR/nohup.log\n"
fi

####
# wait for the puppets
####
echo "Waiting for $count puppets (+ local)"

oldcount=0
elapsed=0

while true
do
  nohupcount=$(ls $RH_DIR/puppets/*.nohup 2> /dev/null | wc -w)
  #echo $nohupcount nohups

  # $count + 1 (local puppet)
  if [ $nohupcount -gt $count ]
  then
    break
  fi

  if [ $nohupcount -gt $oldcount ]
  then
    echo -n "$nohupcount "
    oldcount=$nohupcount
  fi

  echo -n "."

  sleep 2
  elapsed=$(($elapsed + 2))
  m=$(($elapsed % 60))
  if [ $m -eq 0 ]
  then
    minutes=$(($elapsed / 60))
    echo -ne "(${GREEN}$minutes min${NC})"
  fi
done

# Stop monitoring in bottom left window
if [ $cmd != "send" ]
then
  # $'\003' instead of ^C
  screen -S rh -p 1 -X stuff ^C
fi

####
# Make sure the command went right on every puppet
####
echo "Verifying"

ok=1
err_nohups=""
err_count=0
cancel_count=0

for c in $(ls $RH_DIR/puppets/*.nohup)
do
  grep "^RHCANCEL$" $c 2>&1 > /dev/null
  if [ $? -eq 0 ]
  then
    cancel_count=$((cancel_count + 1))
  fi

  grep "^RHOK$" $c 2>&1 > /dev/null

  if [ $? -ne 0 ]
  then
    basename=$(basename $c)
    err_nohups="$err_nohups ${basename%.nohup}"
    err_count=$((err_count + 1))
    ok=0
  fi
done

if [ $ok -eq 1 ]
then
  if [ $cancel_count -eq 0 ]
  then
    echo -e "${GREEN}Success!${NC}"
  else
    echo "Command cancelled"
  fi

  # Keep an history of all commands that have succeeded
  echo $(date "+%d/%m/%Y %H:%M") $RH_PATH $cmdline >> $RH_DIR/history

  if [ $cmd == "restore" ]
  then
    touch $RH_DIR/$system.restore
  fi
else
  echo -e "${RED}Error on $err_count/$count+1 puppets${NC}; check .nohup files for:"
  echo "$err_nohups"
  exit 1
fi

exit 0
