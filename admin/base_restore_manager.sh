#!/bin/bash
base_r="/etc/restore/base_restore.conf"
base_tmp="/etc/restore/base_restore.tmp"
nbr_sys=0
nbr_sys=$(grep "^nbr_systemes" $base_r | cut -d: -f2)
j=1

num_ligne_aj=0
nouv_nbr_sys=0

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

echo "	Restore Hope - base_restore_manager automatique v0.91 (08/10/2010)"
echo "	IUT R/T Vitry - Anthony Delaplace, Brice Augustin, Benoit Albert et Coumaravel Soupramanien"
echo ""
echo "	Systèmes disponibles : "
while [ $j -le $nbr_sys ]
do
	echo "$(grep "^$j" $base_r | cut -d: -f1) $(grep "^$j" $base_r | cut -d: -f2) $(grep "^$j" $base_r | cut -d: -f3) $(grep "^$j" $base_r | cut -d: -f4) $(grep "^$j" $base_r | cut -d: -f5)"
	j=`expr $j + 1`
done

echo -n "	Souhaitez-vous ajouter une ligne (a) ou en supprimer une (s) ? : "

read reponse

if [ "$reponse" = "a" -o "$reponse" = "A" -o "$reponse" = "s" -o "$reponse" = "S" ]
then
	if [ "$reponse" = "a" -o "$reponse" = "A" ]
	then
		num_ligne_aj=`expr $nbr_sys + 1`
		nouv_nbr_sys=`expr $nbr_sys + 1`
	
		echo "Entrez le nom du systeme (ex debian lenny ver 2) : "
		read nom_sys_aj
		echo "Entrez le chemin de la partition (ex /dev/sda1) : "
		read chemin_aj
		echo "Entrez le nom de l'image (ex img_2k3v2.pm.gz.000) : "
		read nom_img_aj
		echo "Entrez le type de systeme de fichiers (ex ntfs ou ext4) : "
		read type_fs
		echo "" >> $base_r
		echo "$num_ligne_aj:$nom_sys_aj:$chemin_aj:$nom_img_aj:$type_fs" >> $base_r
		[ $? -eq 0 ] && echo "la ligne a ete ajoute"
		sed "s/^nbr_systemes:$nbr_sys/nbr_systemes:$nouv_nbr_sys/" $base_r > $base_tmp
		cat $base_tmp > $base_r		

		[ $? -eq 0 ] && echo "Le changement a ete effectue"
	fi

	if [ "$reponse" = "s" -o "$reponse" = "S" ]
	then
		echo "Quelle ligne voulez-vous supprimer ? : "
		read num_ligne_supp
		sed -e "/^$num_ligne_supp:/d" $base_r > $base_tmp
		cat $base_tmp > $base_r		

		nouv_nbr_sys=`expr $nbr_sys - 1`
		sed -e "s/^nbr_systemes:$nbr_sys/nbr_systemes:$nouv_nbr_sys/" $base_r > $base_tmp
		cat $base_tmp > $base_r

		num_lign_a_modifer=`expr $num_ligne_supp + 1`
		
		while [ $num_lign_a_modifer -le $nbr_sys ]
		do
			num_ligne_modife=`expr $num_lign_a_modifer - 1`
			sed -e "s/^$num_lign_a_modifer:/$num_ligne_modife:/" $base_r > $base_tmp
			
			cat $base_tmp > $base_r
			num_lign_a_modifer=`expr $num_lign_a_modifer + 1`
		done
	
	fi
	
	cat $base_r | uniq > $base_tmp
	mv $base_tmp $base_r
	
else
	echo "Mauvais choix !!!"
fi 


