#!/bin/bash

# Source :
# https://pve.proxmox.com/wiki/Install_Proxmox_VE_on_Debian_Stretch

gw=$(ip route | grep default | cut -d ' ' -f 3)

if [ "$gw" == "" ]
then
  echo "Pas de connexion, stop."
  exit
fi

# On suppose que le réseau est un /24
netid=$(cut -d '.' -f1-3 <<< $gw)

ipaddr="$netid.42"

hostname=$(hostname)

# On suppose qu'il n'y a qu'une seule carte réseau
# TODO : prévoir le cas du PC central avec plusieurs cartes
cat > /etc/network/interfaces << EOF
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet manual

auto vmbr0
iface vmbr0 inet static
  address $ipaddr/24
  gateway $gw
  bridge_ports eth0
EOF

# Supprimer la ligne liant le nom de l'hôte à l'IP locale (Proxmox n'aime pas)
sed -i -E '/^127.0.1.1/d' /etc/hosts

# Ajouter une entrée qui lie le nom de l'hôte à son IP
sed -i -E '/^127.0.0.1/a\'$ipaddr' '$hostname /etc/hosts

# Dépôt Proxmox
echo "deb http://download.proxmox.com/debian/pve stretch pve-no-subscription" > /etc/apt/sources.list.d/pve-install-repo.list

# Clé du dépôt Proxmox
wget http://download.proxmox.com/debian/proxmox-ve-release-5.x.gpg -O /etc/apt/trusted.gpg.d/proxmox-ve-release-5.x.gpg

# TODO : automatiser les questions posées (grub -> Ne pas l'installer)
apt update && apt dist-upgrade

# TODO : automatiser les questions posées (postfix -> Site local)
apt install proxmox-ve postfix open-iscsi

# XXX Prend souvent des plombes (ou freeze ?)

pushd prep
./masterprep.sh
popd
