#!/bin/bash

#if [ $# -lt 1 ]
#then
#  echo "XXX"
#  exit
#fi

#filepath=$1
#basename=$(basename $filepath)
#dirname=$(dirname $filepath)

#echo "stopping dhcp"
#systemctl stop isc-dhcp-server
#echo "deleting lease files"
#rm /var/lib/dhcp/dhcpd.leases~
#echo "" > /var/lib/dhcp/dhcpd.leases
#echo "starting dhcp"
#systemctl start isc-dhcp-server

#screen -S rh -p 1 -X stuff '\n'

echo "Waiting for an IP address "

while true
do
  netif=$(ip route | grep default | awk '{print $5}')

  if [ "$netif" != "" ]
  then
    break
  fi

  echo -n .
  sleep 2
done

echo ""

netip=$(ip -o -4 a list $netif | awk '{print $4}' | cut -d '/' -f1)

echo "netif $netif $netip"

echo "Waiting for clients. Press Enter when ready."

if [ -d $RH_DIR/puppets ]
then
  rm -rf $RH_DIR/puppets
fi

mkdir $RH_DIR/puppets
chmod 777 $RH_DIR/puppets

rm $RH_DIR/*.restore 2> /dev/null

oldcount=0

while true
do
  echo -n "."
  echo glop | socat - UDP-DATAGRAM:255.255.255.255:24000,bind=$netip,broadcast

  read -t 3 n
  if [ $? -eq 0 ]
  then
    break
  fi

  count=$(ls $RH_DIR/puppets | wc -w)
  if [ $count -gt $oldcount ]
  then
    echo -n "$count "
    oldcount=$count
  fi

done

# loop client count here (use middle window for something else)

# augmenter durée des baux
#clientip=$(cat /var/lib/dhcp/dhcpd.leases | grep '^lease ' | cut -d ' ' -f 2 | sort | uniq)

clientip=$(ls $RH_DIR/puppets)

count=$(echo $clientip | wc -w)

echo $count puppets

if [ $# -gt 1 ]
then
  echo "./rh2.sh $@"
  $RH_PATH $@
fi
