#!/bin/bash

if [ $EUID -ne 0 ]
then
  echo "Doit être exécuté en tant que root"
  exit
fi

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

ok=0

for i in {0..2}
do
  iface=eth$i
  ip a show dev $iface > /dev/null 2>&1

  if [ $? -eq 0 ]
  then
    echo "auto $iface" >> /etc/network/interfaces
    echo "iface $iface inet dhcp" >> /etc/network/interfaces

    ok=1
  fi
done

# Aucune interface trouvée, abandonner.
# Peut être que le système utilise les "nouveaux" noms de cartes
# TODO : configurer grub pour utiliser les "anciens" noms, puis rebooter ?
if [ $ok -eq 0 ]
then
  echo "Aucune interface eth{0-2} trouvée. Vous devez utiliser les \"anciens\" noms de cartes"
  echo "GRUB_CMDLINE_LINUX=\"net.ifnames=0 biosdevname=0\""
  echo "grub-mkconfig -o /boot/grub/grub.cfg"
  exit
fi

# cd /root
cd


apt-get update
apt-get install -y openssh-server \
                socat \
                beep \
                screen \
                udpcast \
                exfat-fuse \
                ntfs-3g \
                partclone

# Pas de passphrase, écraser (y) la clé si elle existe déjà
yes y | ssh-keygen -f /root/.ssh/id_rsa -N ""

# Copie de la clé publique dans les clés autorisées pour la connexion SSH
cp .ssh/id_rsa.pub .ssh/authorized_keys

# Autoriser la connexion SSH avec le login root
sed '/PermitRootLogin/s/^.*$/PermitRootLogin yes/' /etc/ssh/sshd_config

# Ne pas faire de résolution DNS
sed -i -E 's/#UseDNS /UseDNS /' /etc/ssh/sshd_config

# Redémarrer le serveur SSH
systemctl restart sshd

# Désactiver la vérification de la clé du serveur
echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config
echo "UserKnownHostsFile /dev/null" >> /etc/ssh/ssh_config

# Copier les scripts
cp rhstart.sh initrh2.sh rh2.sh receive.sh restore2.sh puppet.sh rhquit.sh /usr/local/sbin/

# Les rendre exécutables
# Pas besoin, git préserve les droits d'exécution

# Créer le répertoire de RH
mkdir /root/rh2
