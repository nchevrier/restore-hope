# restore-hope

Gestion des salles de TP Réseaux

## Utilisation

- Pour les étudiants : restauration, à la demande, de n'importe quel OS

- Pour les techs/profs : administration massive des postes

## Installation

Prérequis :

- Une installation Debian (*etudiant*) avec tasksel `GNOME` et `Utilitaires de base`
- Une installation Debian (*RH*) sans aucun tasksel
- Eventuellement, un ou plusieurs autres OS (Windows, Proxmox, etc.).

Dans un terminal root sur la Debian RH :

```
export https_proxy=http://proxy.iutcv.fr
apt-get install wget unzip
wget --no-check-certificate https://github.com/brice-augustin/restore-hope/archive/master.zip
unzip master.zip
cd restore-hope-master
./install.sh [login]
```

Si le paramètre `login` est renseigné, l'utilisateur doit entrer le mot de passe root pour lancer une restauration.
