#!/bin/bash

export PROXYIUT="proxy.iutcv.fr"
export PROXYIUT_PORT="3128"

# On aura besoin du proxy pendant les installations !
export https_proxy=http://$PROXYIUT:$PROXYIUT_PORT
export http_proxy=http://$PROXYIUT:$PROXYIUT_PORT

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
# Paquetages
####

apt-get update -y
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
mkdir -p ~/rh2

####
#
####

mkdir -p /etc/restore
mkdir -p /home/restore/
echo nbr_systemes:0 > /etc/restore/base_restore.conf
rh_syst_count=0

####
# Lancer restore2.sh sur tty au démarrage
####

# Drop-in pour tty1
# https://askubuntu.com/questions/659267/how-do-i-override-or-configure-systemd-services
# Bug : Cannot edit units if not on a tty
#SYSTEMD_EDITOR=tee systemctl edit getty@tty1 << EOF

mkdir -p /etc/systemd/system/getty\@tty1.service.d

cat > /etc/systemd/system/getty\@tty1.service.d/override.conf << EOF
[Service]
ExecStartPre=/bin/sh -c 'setleds -D +num < /dev/%I'
ExecStart=
ExecStart=-/sbin/agetty --noclear %I $TERM -n -i -l /usr/local/sbin/restore2.sh
EOF

#cmdline='-\/sbin\/agetty --noclear %I $TERM -i -n -l \/usr\/local\/sbin\/restore2.sh'
#sed -i --follow-symlinks "s/^ExecStart=.*$/ExecStart=$cmdline/" /etc/systemd/system/getty.target.wants/getty\@tty1.service

####
# Grub : préparation
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

####
# Post install du Debian etudiant
####

wget --no-check-certificate https://github.com/brice-augustin/debian-etudiant/archive/master.zip -O master.zip

unzip -o master.zip

# Faire une sauvegarde des scripts de préparation du master (pour RH, plus tard)
cp -r debian-etudiant-master/prep .

mountdir="/mnt/debian-etudiant"
mkdir -p $mountdir

# Utiliser os-prober pour trouver le Debian etudiant
count=$(os-prober | grep linux | wc -l)
if [ $count -ne 1 ]
then
  echo "Il existe plusieurs autres OS Linux sur le disque. Arrêt."
  exit
fi

debianpart=$(os-prober | grep linux | cut -d ':' -f1)

rh_syst_count=$((rh_syst_count + 1))
echo "$rh_syst_count:Linux:$debianpart:/home/restore/img_debian.pcl.gz:ext4" >> /etc/restore/base_restore.conf

# Monter le Debian etudiant
mount $debianpart $mountdir
mount -t proc proc $mountdir/proc/
mount --rbind /sys $mountdir/sys/
mount --rbind /dev $mountdir/dev/
# Eviter des warnings
mount --bind /dev/pts $mountdir/dev/pts

# resolv.conf de Debian etudiant pointe sur un fichier du Network Manager
rm -rf $mountdir/etc/resolv.conf
cp /etc/resolv.conf $mountdir/etc

# mv ne fonctionne pas entre deux partitions
cp -r debian-etudiant-master $mountdir/root

# Exécuter postinstall dans le chroot
chroot $mountdir /bin/bash -c "cd /root/debian-etudiant-master; ./postinstall.sh"

# Installer grub avant de copier default/grub, sinon apt couine
# (demande de choisir entre les deux versions de fichiers)
chroot $mountdir /bin/bash -c "apt-get install -y grub-efi-amd64"

# Copier le fichier de conf grub de RH sur le Debian etudiant
cp /etc/default/grub $mountdir/etc/default

# Génère une unique entrée (pour le Debian etudiant)
# Ne pas ajouter d'entrée "setup" pour EFI
# Ne pas prober les autres OS
chroot $mountdir /bin/bash -c "chmod a-x /etc/grub.d/30_uefi-firmware \
    && chmod a-x /etc/grub.d/30_os-prober \
    && update-grub \
    && cp /boot/grub/grub.cfg /root/grub.cfg \
    && apt-get remove -y --purge grub* \
    && mkdir -p /boot/grub \
    && cp /root/grub.cfg /boot/grub"

# --lazy si démontage refusé à cause d'un fichier en cours d'utilisation (systemd)
# -- recursive
umount --lazy $mountdir

####
# Grub finalisation
####

# Générer grub.cfg (Windows et Debian etudiant sont découverts et ajoutés
# par os_prober. Dans le cas de Debian etudiant, si os_prober trouve un
# grub.cfg sur cette partition, il ajoute les entrées de ce fichier
# (normalement il n'y en aura qu'une)
update-grub

# Renommer les entrées crées dans grub.cfg :
# 1) Restore Hope
# Substitue toutes les occurences de '[^']*', même si la ligne
# ne contient pas menuentry !
#sed -i "0,/menuentry /s/'[^']*'/'Restauration'/" /boot/grub/grub.cfg
# Si "menuentry" au lieu de "menuentry " : pas de substitution !
sed -i "0,/menuentry /s/'[^']*Linux[^']*'/'Restauration'/" /boot/grub/grub.cfg

# 2) Windows
sed -i "/menuentry /s/'Windows[^']*'/'Windows'/" /boot/grub/grub.cfg

# 3) Debian etudiant
sed -i "/menuentry /s/'[^']*Linux[^']*sur[^']*'/'Debian Linux'/" /boot/grub/grub.cfg

# grub-install sur la partition EFI
c=$(fdisk -l | grep EFI | wc -l)
if [ $c -eq 1 ]
then
  efipart=$(fdisk -l | grep EFI | cut -d ' ' -f1)
  grub-install $efipart
else
  echo "Il existe plusieurs partitions EFI."
  echo "A vous de lancer grub-install sur la bonne."
fi

####
# base_restore.conf
####
mountdir="/mnt/windows"
mkdir -p $mountdir

for p in $(fdisk -l | grep Microsoft | cut -d ' ' -f 1)
do
  if blkid $p | grep ntfs > /dev/null 2>&1
  then
    mount $p $mountdir

    rh_syst_count=$((rh_syst_count + 1))
    if [ -d $mountdir/Windows ]
    then

      if grep "WINDOWS SERVER" $mountdir/Windows/System32/license.rtf > /dev/null 2>&1
      then
        echo "$rh_syst_count:Windows Server:$p:/home/restore/img_win16.pcl.gz:ext4" >> /etc/restore/base_restore.conf
      else
        echo "$rh_syst_count:Windows 10:$p:/home/restore/img_win10.pcl.gz:ext4" >> /etc/restore/base_restore.conf
      fi
    else
      echo "$rh_syst_count:DATA:$p:/home/restore/img_data.pcl.gz:ext4" >> /etc/restore/base_restore.conf
    fi

    umount $mountdir
  fi
done


####
# Finalisation
# (proxy, interfaces, ifup-hook, setleds)
####
pushd prep
./masterprep.sh
popd

# Exec at the very end, otherwise the rest of the script will not be executed
#systemctl restart getty@tty1
