#!/bin/bash

export RH_BIN_DIR="/usr/local/sbin"
export RH_DIR="/root/rh2"

####
# Text colors
####
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

base_r="/etc/restore/base_restore.conf"
nbr_sys=$(grep "^nbr_systemes:" $base_r | cut -d: -f2 )

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

echo "	Restore Hope - Restauration automatique v1.96 (14/07/2018)"
echo "	IUT R/T Vitry - Anthony Delaplace, Brice Augustin, Benoit Albert et Coumaravel Soupramanien"
echo ""
echo "	Systèmes disponibles :"

for i in $(seq 1 $nbr_sys)
do
	partition="$(grep "^$i:" $base_r | cut -d: -f3)"
	num=$(grep "^$i:" $base_r | cut -d: -f1)
	label=$(grep "^$i:" $base_r | cut -d: -f2)
	image=$(grep "^$i:" $base_r | cut -d: -f4)

  # Afficher le système slt si son image existe
	# et que sa taille n'est pas nulle
	if [ -s $image ]
	then
		mount $partition $MOUNTDIR

		echo -n "		$num   $label"

		if [ -f $MOUNTDIR/tainted -o -f $MOUNTDIR/taint/tainted ]
		then
			echo -e "${RED} !${NC}"
		else
			echo ""
		fi

		umount $partition
	else
		echo -e "		${RED}Pas d'image pour le système \"$label\"${NC}"
	fi
done

echo ""
echo -n "	Entrez le numéro du système à restaurer : "

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

	read -t 5 user_input

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

		new_masterip=$(cat $RH_DIR/puppetmode)

		if [ "$masterip" != "" -a "$masterip" != "$new_masterip" ]
		then
			beep -f 600; beep -f 600; beep -f 600
			echo -e "${RED}Detected multiple masters (current: $masterip; new: $new_masterip)${NC}"
			# What should we do?
			# Warn only on the master?
		fi

		masterip=$new_masterip

		setterm -back white -fore green

		netif=$(ip route | grep default | awk '{print $5}')
		netip=$(ip -o -4 a list $netif | awk '{print $4}' | cut -d '/' -f1)

		if [ $netip != $masterip ]
		then
			# Before SSH, verify it is in the same network
			# Trick : do a routing table lookup and check for a "via" statement
			if ip route get $masterip | grep via > /dev/null 2>&1
			then
				echo -e "${RED}Master ($masterip) not directly reachable from $netip${NC}"
				beep 400
			fi

			ssh $masterip "touch $RH_DIR/puppets/$netip" 2> /dev/null
			if [ $? -ne 0 ]
			then
				echo -e "${RED}Cannot connect to master ($masterip)${NC}"
				beep 400
				sleep 10
			else
				echo -e "${GREEN}Master IP: $masterip${NC}"
				echo "Puppet IP: $netip"
			fi
		else
			echo -e "${GREEN}You are the master: $masterip${NC}"
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
		num=${user_input%[rc]}

		image="$(grep "^$num:" $base_r | cut -d: -f4)"

		# image est vide ("") si $num ne correspond à aucun système
		if [ "$image" == "" ]
		then
			echo ""

			for i in {1..18}
			do
				echo "	Quand on me demande un numéro entre 1 et $nbr_sys je donne un numéro entre 1 et $nbr_sys"
			done
		elif [ ! -s "$image" ]
		then
			echo -e "${RED}Pas d'image pour ce système${NC}"
		else
			partition="$(grep "^$num:" $base_r | cut -d: -f3)"
			type="$(grep "^$num:" $base_r | cut -d: -f5)"

			zcat $image | partclone.$type -r -o $partition
			#	partimage restore -b -f1 $partition $image.$fin_img

			# Effacer l'indicateur de restauration
			# (juste au cas où on l'a oublié sur le master)
			mount $partition $MOUNTDIR
			[ -f $MOUNTDIR/tainted ] && rm $MOUNTDIR/tainted
			[ -f $MOUNTDIR/taint/tainted ] && rm $MOUNTDIR/taint/tainted
			umount $MOUNTDIR

			if [[ $user_input =~ r$ ]]
			then
				reboot
			elif [[ $user_input =~ c$ ]]
			then
				exit
			else
				init 0
			fi
		fi

		sleep 5
		exit
	# User input
	fi
done
