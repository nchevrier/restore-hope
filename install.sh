#!/bin/bash

####
# Déterminer si on doit utiliser le proxy ou pas
# Truc utilisé : si l'install a été faite avec le proxy, celui-ci
# est configuré dans APT
####
# apt.conf n'existe pas si le proxy n'est pas configuré à l'install
p=$(grep "^Acquire::http::Proxy" /etc/apt/apt.conf | cut -d'"' -f 2)

if [ "$p" != "" ]
then
  tmp=${p%:*}
  export PROXYIUT=${tmp#http://}

  export PROXYIUT_PORT=${p##*:}

  # Configurer temporairement le proxy (pour les curl, wget, etc. du script)
  export http_proxy="http://$PROXYIUT:$PROXYIUT_PORT"
  export https_proxy="http://$PROXYIUT:$PROXYIUT_PORT"
  export ftp_proxy="http://$PROXYIUT:$PROXYIUT_PORT"
fi

if [ $EUID -ne 0 ]
then
  echo "Doit être exécuté en tant que root"
  exit
fi

RH_CONF="/etc/restore/base_restore.conf"
LOGFILE=.restore-hope.log

rm $LOGFILE &> /dev/null

####
# Paramètres
####
ENABLE_LOGIN=0
PRESERVE_KEY=0

if [ $# -eq 1 ]
then
  if [ $1 == "login" ]
  then
    echo "Le mot de passe root sera demandé avant la restauration d'un OS"
    ENABLE_LOGIN=1
  elif [ $1 == "preserve" ]
  then
    echo "On garde la clé RSA actuelle"
    PRESERVE_KEY=1
  fi
fi

####
# Requis : une carte branchée avec accès internet
# TODO : tenter de configurer la carte si on détecte un câble branché ?
####

netif=$(ip route | grep default)

if [ $? -ne 0 ]
then
  echo "Pas de connexion réseau. Impossible de continuer."
  exit
fi

####
# Paquetages
####

apt-get update -y >> $LOGFILE 2>&1
apt-get install -y openssh-server \
                socat \
                beep \
                unzip \
                screen \
                ethtool \
                udpcast \
                exfat-fuse \
                ntfs-3g \
                partclone >> $LOGFILE 2>&1

# Pour nettoyage après chroot. Désinstaller après ?
apt-get install -y lsof >> $LOGFILE 2>&1

# Pour la loterie
apt-get install -y cmatrix >> $LOGFILE 2>&1

####
# SSH
####

# Quick and dirty fix : garder la clé RSA actuelle
# si l'utilisateur le demande (utile pour la màj de Restore Hope
# en parallèle sur tous les systèmes (sans clonage)
if [ $PRESERVE_KEY -eq 0 ]
then
  # Pas de passphrase, écraser (y) la clé si elle existe déjà
  yes y | ssh-keygen -f ~/.ssh/id_rsa -N "" >> $LOGFILE 2>&1

  # Copie de la clé publique dans les clés autorisées pour la connexion SSH
  cp ~/.ssh/id_rsa.pub ~/.ssh/authorized_keys
fi

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

# Petite musique de victoire
cp nudge/*.sh /usr/local/sbin/

# Les rendre exécutables
# Pas besoin, git préserve les droits d'exécution

# Créer le répertoire de RH
mkdir -p ~/rh2

# Créer le répertoire pour monter une clé USB
mkdir -p /mnt/usb

####
# Préparer la conf de RH
####

mkdir -p /etc/restore
mkdir -p /home/restore/
echo -n "" > $RH_CONF
rh_syst_count=0

####
# Lancer restore2.sh au démarrage
####

if [ $ENABLE_LOGIN -eq 0 ]
then
  # Pas de login au démarrage
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
else
  # Exécuter restore2.sh sur tty1, mais après le login
  cat >> /root/.bashrc << EOF

tty=$(tty)
if [ "\$tty" == "/dev/tty1" ]
then
	/usr/local/sbin/restore2.sh
fi
EOF

fi

####
# Grub : préparation de la conf
# Structure actuelle d'un disque :
# sda4 windows10
# sda5 windows2016
# sda6 partage
# sda7 swap
# sda8 debian etudiant
# sda9 RH
####

# Anciens noms de cartes réseau (eth0, pas ens33 ou enp0s3)
# https://www.itzgeek.com/how-tos/linux/debian/change-default-network-name-ens33-to-old-eth0-on-debian-9.html
# Vérifier le nommage utilisé
if ! grep "^GRUB_CMDLINE_LINUX=.*net.ifnames=0" /etc/default/grub > /dev/null 2>&1
then
  # ajouter net.ifnames=0 biosdevname=0
  # Sera appliqué au Debian RH mais aussi au Debian etudiant
  sed -i '/GRUB_CMDLINE_LINUX=/s/"$/ net.ifnames=0 biosdevname=0"/' /etc/default/grub

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
# D/l l'installateur Debian etudiant, utilisé dans deux parties :
# - (Inconditionnel) Préparation du master de RH
# - (Ssi un autre Debian est détecté) Installation du Debian etudiant en chroot
####
wget --no-check-certificate https://github.com/brice-augustin/debian-etudiant/archive/master.zip -O master.zip

unzip -o master.zip >> $LOGFILE 2>&1

# Faire une sauvegarde des scripts de préparation du master (pour RH, plus tard)
cp -r debian-etudiant-master/prep .

####
# Post install du Debian etudiant (si présent)
####

# Utiliser os-prober pour trouver le Debian etudiant
count=$(os-prober | grep linux | wc -l)

# Une seule autre partition Linux sur le dique. C'est forcément le Debian etudiant
if [ $count -eq 1 ]
then
  mountdir="/mnt/debian-etudiant"
  mkdir -p $mountdir

  debianpart=$(os-prober | grep linux | cut -d ':' -f1)

  rh_syst_count=$((rh_syst_count + 1))
  echo "$rh_syst_count:Linux:$debianpart:/home/restore/img_debian.pcl.gz:ext4" >> $RH_CONF

  # Monter le Debian etudiant
  mount $debianpart $mountdir
  # http://shallowsky.com/blog/tags/chroot/
  mount --bind /dev $mountdir/dev/
  mount --bind /proc $mountdir/proc/
  mount --bind /sys $mountdir/sys/
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
  chroot $mountdir /bin/bash -c "apt-get install -y grub-efi-amd64" >> $LOGFILE 2>&1

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
      && mv /root/grub.cfg /boot/grub" >> $LOGFILE 2>&1

  # Supprimer les scripts sur le Debian etudiant
  cp $mountdir/root/debian-etudiant-master/.debian-etudiant.log .
  rm -rf $mountdir/root/debian-etudiant-master

  # --lazy si démontage refusé à cause d'un fichier en cours d'utilisation (systemd)
  # -- recursive
  # Ne pas utiliser : freeze le reboot suivant (pourquoi ?)
  # umount --lazy $mountdir
  # https://unix.stackexchange.com/questions/61885/how-to-unmount-a-formerly-chrootd-filesystem
  umount $mountdir/dev/pts

  # Toujours une erreur à cause de /dev/null utilisé par des process !
  # Peut-être lié aux dbus-launch ?
  # Tout nettoyer avant démontage de dev
  for pid in $(lsof | grep $mountdir/dev | awk '{print $2}' | sort | uniq)
  do
    kill $pid
  done

  umount $mountdir/dev/
  umount $mountdir/proc/
  umount $mountdir/sys/
  umount $mountdir

# Plusieurs partitions Linux. On ne sait pas laquelle est la Debian etudiant
elif [ $count -gt 1 ]
then
  echo "Il existe plusieurs autres OS Linux sur le disque. Arrêt."
  exit
fi

####
# Grub finalisation
####

# Générer grub.cfg (Windows et Debian etudiant sont découverts et ajoutés
# par os_prober. Dans le cas de Debian etudiant, si os_prober trouve un
# grub.cfg sur cette partition, il ajoute les entrées de ce fichier
# (normalement il n'y en aura qu'une; voir plus haut)
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

# Sauvegarder grub.cfg au cas où il est détruit
cp /boot/grub/grub.cfg /home/restore/grub.cfg

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
        echo "$rh_syst_count:Windows Server:$p:/home/restore/img_win16.pcl.gz:ntfs" >> $RH_CONF
      else
        echo "$rh_syst_count:Windows 10:$p:/home/restore/img_win10.pcl.gz:ntfs" >> $RH_CONF
      fi
    else
      echo "$rh_syst_count:DATA:$p:/home/restore/img_data.pcl.gz:ntfs" >> $RH_CONF
    fi

    umount $mountdir
  fi
done

# grub-install sur la partition EFI
# Après toutes les autres pour éviter un "trou" dans la numérotation des systèmes
c=$(fdisk -l | grep EFI | wc -l)
if [ $c -eq 1 ]
then
  efipart=$(fdisk -l | grep EFI | cut -d ' ' -f1)
  grub-install $efipart

  # Ajouter une entrée dans le fichier de conf de RH
  rh_syst_count=$((rh_syst_count + 1))
  echo "$rh_syst_count:Boot UEFI:$efipart:/home/restore/img_efi.FAKE.gz:efi" >> $RH_CONF
  # Eviter que le script de restauration affiche un avertissement
  # sur l'inexistence d'une image pour ce système
  echo "FAKE" > /home/restore/img_efi.FAKE.gz
else
  echo "Impossible de trouver la partition EFI."
  echo "A vous de lancer grub-install sur la bonne."
fi

echo "nbr_systemes:$rh_syst_count" >> $RH_CONF

####
# Finalisation
# (proxy, interfaces, ifup-hook, setleds)
####
pushd prep
./masterprep.sh
popd

# Exec at the very end, otherwise the rest of the script will not be executed
#systemctl restart getty@tty1

echo "Installation terminée."
echo "Ne pas démarrer Debian etudiant et Restore Hope avant de déployer le master."
# Si c'est le cas, sur le Linux qui a été démarré :
# systemctl enable init-interfaces.service
# systemctl daemon-reload
