#!/bin/bash

export RH_BIN_DIR="/usr/local/sbin"
export RH_DIR="/root/rh2"

####
# Text colors
####
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

RH_CONF="/etc/restore/base_restore.conf"
nbr_sys=$(grep "^nbr_systemes:" $RH_CONF | cut -d: -f2 )

MOUNTDIR=/mnt/os
mkdir -p $MOUNTDIR

function loterie_nudge {
  # N'affiche rien avec cmatrix dans un script ... A partir d'un terminal, pas de problème !
  #timeout 5 cmatrix

  # Lancer cmatrix en background et récupérer son PID
  cmatrix &
  pid=$!

  sleep 10

  # Envoyer un Ctrl-C à cmatrix
  kill -INT $pid

  # "Réparer" le tty (pas de retour à la ligne ni d'écho de caractère
  # après la destruction de cmatrix
  stty sane

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

  numero=$((RANDOM % 1000))

  if [ $numero -eq 42 ]
  then
    echo -e "	${GREEN}VOUS REMPORTEZ LE GROS LOT !!!${NC}"

    for i in {1..3}
    do
      $RH_BIN_DIR/mario-victory.sh
      sleep 10
    done

    sleep 120
  else
    echo -e "	${RED}Perdu !${NC} Retentez votre chance à la fin du prochain TP !"
    sleep 10
  fi

  echo ""
  echo ""
  echo ""
}

function restore_partition {
  num=$1

  return_value=0

  image=$(grep "^$num:" $RH_CONF | cut -d ':' -f4 )
  partition=$(grep "^$num:" $RH_CONF | cut -d ':' -f 3)
  type=$(grep "^$num:" $RH_CONF | cut -d ':' -f 5)

  # Nettoyage des entrées UEFI (si Windows a mis le bazard)
  if [ "$type" == "efi" ]
  then
    echo "Restauration du boot UEFI ..."
    # Effacer toutes les entrées actuelles
    for res in $(efibootmgr -v | grep -E "(debian|Microsoft)" | grep -E "^Boot[0-9]" | cut -d ' ' -f 1)
    do
      id=${res:4:4}
      # Quiet mode sinon affiche la totalité des entrées EFI
      efibootmgr -q -B -b $id
    done

    # Ajout d'une nouvelle entrée EFI"
    # XXX -p 2 indique la partition EFI se trouve dans sda2.
    disk=${partition%?}
    partnum=$(echo -n $partition | tail -c 1)
    efibootmgr -q -c -d $disk -p $partnum -L "RESTORE-HOPE" -l "\EFI\debian\grubx64.efi"

    # Numéro de la nouvelle entrée
    res=$(efibootmgr | grep "RESTORE-HOPE")
    id=${res:4:4}

    # Changer le boot order
    efibootmgr -q -o $id

    sleep 5

    return 0
  fi

  # image est vide ("") si $num ne correspond à aucun système
  if [ "$image" == "" ]
  then
    echo ""

    for i in {1..18}
    do
      echo "	Quand on me demande un numéro entre 1 et $nbr_sys je donne un numéro entre 1 et $nbr_sys"
    done

    return_value=1
  elif [ ! -s "$image" ]
  then
    echo -e "${RED}	Pas d'image pour ce système${NC}"
    return_value=1
  else
    echo ""
    echo ""
    echo -n -e "${GREEN}	Nouveau !${NC} Appuyez sur Entrée pour participer à la Loterie R&T ... "

    read -t 5 loterie_input

    # Pas un timeout
    if [ $? -eq 0 ]
    then
      loterie_nudge
    fi

    set -o pipefail

    zcat $image | partclone.$type -r -o $partition

    return_value=$?

    set +o pipefail

    # Effacer l'indicateur de restauration
    # (juste au cas où on l'a oublié sur le master)
    mount $partition $MOUNTDIR
    [ -f $MOUNTDIR/tainted ] && rm $MOUNTDIR/tainted
    [ -f $MOUNTDIR/taint/tainted ] && rm $MOUNTDIR/taint/tainted
    umount $MOUNTDIR

  fi

  return $return_value
}

# Le script est invoqué en mode non-interactif.
# Exécuter la commande demandée puis stopper.
if [ $# -gt 0 ]
then
  restore_partition $1
  exit
fi

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

echo "	Restore Hope - Restauration automatique v1.97 (13/02/2019)"
echo "	IUT R/T Vitry - Anthony Delaplace, Brice Augustin, Benoit Albert et Coumaravel Soupramanien"
echo ""
echo "	Systèmes à restaurer :"

for i in $(seq 1 $nbr_sys)
do
  partition="$(grep "^$i:" $RH_CONF | cut -d: -f3)"
  num=$(grep "^$i:" $RH_CONF | cut -d: -f1)
  label=$(grep "^$i:" $RH_CONF | cut -d: -f2)
  image=$(grep "^$i:" $RH_CONF | cut -d: -f4)

  # Afficher le système slt si son image existe
  # et que sa taille n'est pas nulle
  if [ -s $image ]
  then
    # If Windows is in hibernation state, mount fails
    mount $partition $MOUNTDIR &> /dev/null
    mount_OK=$?

    echo -n "		$num   $label"

    # If could not mount partition, consider it tainted
    if [ -f $MOUNTDIR/tainted -o -f $MOUNTDIR/taint/tainted -o $mount_OK -ne 0 ]
    then
      echo -e "${RED} !${NC}"
    else
      echo ""
    fi

    umount $partition &> /dev/null
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

    restore_partition $num

    ret=$?

    sleep 5

    # If the requested command worked well, continue.
    if [ $ret -eq 0 ]
    then
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

    exit
  fi
done
