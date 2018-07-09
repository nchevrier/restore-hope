# restore-hope
Système de gestion des salles de TP

- Pour les étudiants :

Restauration à la demande de n'importe quel OS

- Pour les techs/profs :

Administration massive des postes

- Installation

Prérequis : une installation Debian ("etudiant") avec taskset GNOME et Utilitaires de base
et une installation Debian ("RH") sans aucun taskset.

Dans un terminal root sur la Debian RH :

`export https_proxy=http://proxy.iutcv.fr`

`apt-get install wget unzip`

`wget --no-check-certificate https://github.com/brice-augustin/restore-hope/archive/master.zip`

`unzip master.zip`

`cd restore-hope-master`

`./install.sh`
