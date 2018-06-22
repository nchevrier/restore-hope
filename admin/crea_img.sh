#!/bin/bash
base_r="/etc/restore/base_restore.conf"
nbr_sys=$(grep "^nbr_systemes" $base_r | cut -d: -f2 )
num=0
j=1
quest_crea=1

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

	echo "	Restore Hope - Créaton d'image automatique v0.91 (08/10/2010)"
	echo "	IUT R/T Vitry - Anthony Delaplace, Brice Augustin et Benoit Albert"
	echo ""
	echo "	Systémes disponibles :"
	while [ $j -le $nbr_sys ]
	do
		echo "		$(grep "^$j:" $base_r | cut -d: -f1)   $(grep "^$j:" $base_r | cut -d: -f2)"
		echo ""
		echo "      Dont l'mage est $(grep "^$j:" $base_r | cut -d: -f4) et la partition est $(grep "^$j:" $base_r | cut -d: -f3)"
		j=`expr $j + 1`
	done

	echo ""
	echo -n "	Entrez le numero du systeme pour la creation d'image : "

	read num

	echo "Voulez vous creer l 'image $(grep "^$num:" $base_r | cut -d: -f4) de la partition $(grep "^$num:" $base_r | cut -d: -f3 ) (o,n)?"
	read quest_crea

	if [ "$quest_crea" = "o" -o "$quest_crea" = "O" ]
	then

		chemin="0"
		image="0"

		chemin="$(grep "^$num:" $base_r | cut -d: -f3)"
		image="$(grep "^$num:" $base_r | cut -d: -f4)"

		if [ "$chemin" != "0" -a "$image" != "0" -a $num -ne 0 -a $? -eq 0 ]
		then
			partimage -z1 -o -b -d save $chemin $image
			[ $? -ne 0 ] && echo "Il y a eu un petit probleme"
		fi

	fi


