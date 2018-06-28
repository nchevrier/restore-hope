#!/bin/bash

PROXYIUT="http://proxy.iutcv.fr:3128"

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
# Proxy
####

echo "http_proxy=$PROXYIUT" >> /etc/bash.bashrc
echo "https_proxy=$PROXYIUT" >> /etc/bash.bashrc
echo "ftp_proxy=$PROXYIUT" >> /etc/bash.bashrc

echo "Acquire::http::Proxy \"$PROXYIUT\";" > /etc/apt/apt.conf.d/80proxy

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
yes y | ssh-keygen -f ~/.ssh/id_rsa -N ""

# Copie de la clé publique dans les clés autorisées pour la connexion SSH
cp ~/.ssh/id_rsa.pub ~/.ssh/authorized_keys

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
mkdir ~/rh2

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
# Bug : Cannot edit units if not on a tty
#SYSTEMD_EDITOR=tee systemctl edit getty@tty1 << EOF

mkdir /etc/systemd/system/getty\@tty1.service.d

cat > /etc/systemd/system/getty\@tty1.service.d/override.conf << EOF
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
# Bug : Cannot edit units if not on a tty
#SYSTEMD_EDITOR=tee systemctl edit getty@.service << EOF

mkdir /etc/systemd/system/getty\@.service.d

cat > /etc/systemd/system/getty\@.service.d/override.conf << EOF
[Service]
ExecStartPre=/bin/sh -c 'setleds -D +num < /dev/%I'
EOF

####
# Swap
####
# /dev/sda5 -> \/dev\/sda5 sinon sed couine
swap=$(swapon -s | grep "^/dev" | awk '{print $1}' | sed 's/\//\\\//g')

# TODO : remplacer par l'UUID du swap du Debian etudiant (ou l'inverse)
sed -i -E "/ swap /s/^UUID=[^ ]+/$swap/" /etc/fstab

####
# Grub
# sda4 windows10
# sda5 windows2016
# sda6 partage
# sda7 swap
# sda8 etudiant
# sda9 rh
####

# Anciens noms de cartes réseau (eth0, pas ens33 ou enp0s3)
# https://www.itzgeek.com/how-tos/linux/debian/change-default-network-name-ens33-to-old-eth0-on-debian-9.html
# Vérifier le nommage utilisé
if ! grep "^GRUB_CMDLINE_LINUX=.*net.ifnames=0" /etc/default/grub > /dev/null 2>&1
then
  # ajouter net.ifnames=0 biosdevname=0
  # Sera appliqué au Debian RH mais aussi au Debian etudiant
  sed -i '/GRUB_CMDLINE_LINUX/s/"$/ net.ifnames=0 biosdevname=0"/' /etc/default/grub

  # ou update-grub
  # grub-mkconfig -o /boot/grub/grub.cfg
  # Plus tard.
fi

# GRUB_TIMEOUT
sed -i '/GRUB_TIMEOUT=/s/^.*$/GRUB_TIMEOUT=300/' /etc/default/grub

# GRUB_DISABLE_RECOVERY
sed -i '/GRUB_DISABLE_RECOVERY=/s/^.*$/GRUB_DISABLE_RECOVERY=true/' /etc/default/grub

# /etc/grub.d/10_linux GRUB_DISABLE_SUBMENU=y pas true :
# [ "x${GRUB_DISABLE_SUBMENU}" != xy ];
echo "GRUB_DISABLE_SUBMENU=y" >> /etc/default/grub

# Ne pas ajouter d'entrée "setup" pour EFI
chmod a-x /etc/grub.d/30_uefi-firmware

# Supprimer /boot/grub/grub.cfg sur le Debian etudiant
# (Déjà fait lors de l'installation du Debian etudiant)
# grub-efi-amd64

# Générer grub.cfg (Windows et Debian etudiant sont découverts et ajoutés
# par os_prober. Dans le cas de Debian etudiant, si os_prober trouve un
# grub.cfg sur cette partition, il ajoute les entrées de ce fichier
# (ce qu'on ne veut pas)
update-grub

# Renommer les entrées crées dans grub.cfg

# Restore Hope
# Substitue toutes les occurences de '[^']*', même si la ligne
# ne contient pas menuentry !
#sed -i "0,/menuentry /s/'[^']*'/'Restauration'/" /boot/grub/grub.cfg
# Si "menuentry" au lieu de "menuentry " : pas de substitution !
sed -i "0,/menuentry /s/'[^']*Linux[^']*'/'Restauration'/" /boot/grub/grub.cfg

# Windows
sed -i "/menuentry /s/'Windows[^']*'/'Windows'/" /boot/grub/grub.cfg

# Debian etudiant
sed -i "/menuentry /s/'[^']*Linux[^']*sur[^']*'/'Debian Linux'/" /boot/grub/grub.cfg

echo "TODO : grub-install"
# grub-install /dev/sda2

# Exec at the very end, otherwise the rest of the script will not be executed
#systemctl restart getty@tty1

####
# Configuration des interfaces au prochain reboot
# P+VM
####

# Copier script dans /etc/... qui s'exécute au boot et se supprime
cp init-interfaces.sh /usr/local/bin

cat > /etc/systemd/system/init-interfaces.service << EOF
[Unit]
Description=Configuration du fichier interfaces au premier boot

[Service]
Type=oneshot
RemainAfterExit=no
ExecStart=/usr/local/bin/init-interfaces.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl enable init-interfaces.service
