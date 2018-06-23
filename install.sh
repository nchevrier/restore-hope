#!/bin/bash

if [ $EUID -ne 0 ]
then
  echo "Doit être exécuté en tant que root"
  exit
fi

# cd /root
cd

####
# Requis : une carte branchée avec accès internet
# TODO : tenter de configurer la carte si on détecte un câble branché ?
####

netif=$(ip route | grep default)

if [ $? -ne 0 ]
then
  echo "Pas de connexion réseau"
  exit
fi

####
# Configuration dynamique persistante pour toutes les cartes
####

echo "auto lo" > /etc/network/interfaces
echo "iface lo inet loopback" >> /etc/network/interfaces

# Accepter le nouveau nommage des cartes (en) mais aussi l'ancien (eth)
ethif=$(ip -o l show | awk -F': ' '{print $2}' | grep -E "^(eth|en)")

ok=0

for iface in $ethif
do
  ip a show dev $iface > /dev/null 2>&1

  if [ $? -eq 0 ]
  then
    echo "auto $iface" >> /etc/network/interfaces
    echo "iface $iface inet dhcp" >> /etc/network/interfaces

    ok=1
  fi
done

####
# Paquetages
####

apt-get update
apt-get install -y openssh-server \
                socat \
                beep \
                screen \
                udpcast \
                exfat-fuse \
                ntfs-3g \
                partclone

####
# SSH
####

# Pas de passphrase, écraser (y) la clé si elle existe déjà
yes y | ssh-keygen -f /root/.ssh/id_rsa -N ""

# Copie de la clé publique dans les clés autorisées pour la connexion SSH
cp .ssh/id_rsa.pub .ssh/authorized_keys

# Autoriser la connexion SSH avec le login root
sed -i -E '/PermitRootLogin/s/^.*$/PermitRootLogin yes/' /etc/ssh/sshd_config

# Ne pas faire de résolution DNS
sed -i -E 's/#UseDNS /UseDNS /' /etc/ssh/sshd_config

# Redémarrer le serveur SSH
systemctl restart sshd

# Désactiver la vérification de la clé du serveur
echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config
echo "UserKnownHostsFile /dev/null" >> /etc/ssh/ssh_config

####
# Copier les scripts
####

#
cp restore2.sh /usr/local/sbin

# puppet.sh receive.sh
cp puppets/*.sh /usr/local/sbin/

# rhstart.sh initrh2.sh rh2.sh rhquit.sh
cp commander/*.sh /usr/local/sbin/

# base_restore_manager.sh crea_img.sh
cp admin/*.sh /usr/local/sbin/

# Les rendre exécutables
# Pas besoin, git préserve les droits d'exécution

# Créer le répertoire de RH
mkdir /root/rh2

####
#
####

mkdir /etc/restore
echo nbr_systemes:0 > /etc/restore/base_restore.conf

####
# Lancer restore2.sh sur tty au démarrage
####

# Drop-in pour tty1
# https://askubuntu.com/questions/659267/how-do-i-override-or-configure-systemd-services
SYSTEMD_EDITOR=tee systemctl edit getty@tty1 << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noclear %I $TERM -n -i -l /usr/local/sbin/restore2.sh
EOF

#cmdline='-\/sbin\/agetty --noclear %I $TERM -i -n -l \/usr\/local\/sbin\/restore2.sh'
#sed -i --follow-symlinks "s/^ExecStart=.*$/ExecStart=$cmdline/" /etc/systemd/system/getty.target.wants/getty\@tty1.service

####
# setleds
####

# systemd, pas init
# https://wiki.archlinux.org/index.php/Activating_Numlock_on_Bootup#Using_a_separate_service
SYSTEMD_EDITOR=tee systemctl edit getty@.service << EOF
[Service]
ExecStartPre=/bin/sh -c 'setleds -D +num < /dev/%I'
EOF

# Exec at the very end, otherwise the rest of the script will not be executed
#systemctl restart getty@tty1
