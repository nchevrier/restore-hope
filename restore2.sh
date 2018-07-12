#!/bin/bash

export RH_BIN_DIR="/usr/local/sbin"
export RH_DIR="/root/rh2"

#t=$(tty)

#if [ $t != "/dev/tty1" ]
#then
#	/bin/login
#	exit
#fi

####
# Text colors
####
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

base_r="/etc/restore/base_restore.conf"
nbr_sys=$(grep "^nbr_systemes:" $base_r | cut -d: -f2 )
i=0
num="0"
j=1
fin_img="000"

MOUNTDIR=/mnt/os
mkdir -p $MOUNTDIR

clear

echo ""
echo ""
echo ""
echo ""
echo ""
echo ""
echo ""
echo ""
echo ""
echo ""

echo "	Restore Hope - Restauration automatique v1.93 (23/06/2018)"
echo "	IUT R/T Vitry - Anthony Delaplace, Brice Augustin, Benoit Albert et Coumaravel Soupramanien"
echo ""
echo "	Systèmes disponibles :"

while [ $j -le $nbr_sys ]
do
	partition="$(grep "^$j:" $base_r | cut -d: -f3)"
	num=$(grep "^$j:" $base_r | cut -d: -f1)
	label=$(grep "^$j:" $base_r | cut -d: -f2)

	mount $partition $MOUNTDIR

	echo -n "		$num   $label"

	if [ -f $MOUNTDIR/tainted -o -f $MOUNTDIR/taint/tainted ]
	then
		echo -e "${RED} !${NC}"
	else
		echo ""
	fi

	umount $partition
	j=`expr $j + 1`
done

echo ""
echo -n "	Entrez le numero du systeme à restaurer : "

###
# Puppet mode part 1
###
masterip=""

if [ -f $RH_DIR/puppetmode ]
then
	rm $RH_DIR/puppetmode
fi

$RH_BIN_DIR/wait-master.sh &

###
# End part 1
###

while true
do

	read -t 5 num

	read_result=$?

	###
	# Puppet mode part 2
	###
	if [ -f $RH_DIR/puppetmode ]
	then
		# just in case file exists but is not filled yet
		sleep 1

		clear

		echo ""
		echo ""
		echo ""

		masterip=$(cat $RH_DIR/puppetmode)

		setterm -back white -fore green

		netif=$(ip route | grep default | awk '{print $5}')
		netip=$(ip -o -4 a list $netif | awk '{print $4}' | cut -d '/' -f1)

		if [ $netip != $masterip ]
		then
			ssh $masterip "touch $RH_DIR/puppets/$netip" 2> /dev/null
			if [ $? -ne 0 ]
			then
				echo -e "${RED}Cannot connect to master ($masterip)${NC}"
				beep
				sleep 10
			fi
			echo -e "${GREEN}Master IP : $masterip${NC}"
		else
			echo -e "${GREEN}You are the master : $masterip${NC}"
		fi

		rm $RH_DIR/puppetmode

		# restart socat
		$RH_BIN_DIR/wait-master.sh &
		# Wait infinitely
		#sleep infinity
	fi

	# Not a timeout and not in puppet mode :
	# user pressed a key; process and exit
	if [ $read_result -eq 0 -a "$masterip" == "" ]
	then
		partition="$(grep "^$num:" $base_r | cut -d: -f3)"
		image="$(grep "^$num:" $base_r | cut -d: -f4)"
		type="$(grep "^$num:" $base_r | cut -d: -f5)"

		if [ $partition != "0" -a $image != "0" -a $num != "0" -a $? -eq 0 ]
		then
			zcat $image |partclone.$type -r -o $partition
			#	partimage restore -b -f1 $partition $image.$fin_img

			# Effacer l'indicateur de restauration
			# (juste au cas où on l'a oublié sur le master)
			mount $partition $MOUNTDIR
			[ -f $MOUNTDIR/tainted ] && rm $MOUNTDIR/tainted
			[ -f $MOUNTDIR/taint/tainted ] && rm $MOUNTDIR/taint/tainted
			umount $MOUNTDIR

			sleep 5

			init 0
		else
			echo ""

			i=0
			while [ $i -lt 18 ]
			do
				echo "	Quand on me demande un numero entre 1 et $nbr_sys je donne un numero entre 1 et $nbr_sys"
		        	i=`expr $i + 1`
			done

			sleep 5
		fi

		exit
	fi
done
