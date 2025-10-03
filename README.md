# Beacn Utility Update Repositories

This repository houses scripts, resources and CI workflows to build and host update sites
for the Beacn Utility. These sites can be used to install the Beacn Utility, and will be
updated with each new release, allowing for updates to be managed by your package manager.

# Current Support

* Debian based distributions (Ubuntu, Pop!_OS, etc) via an `apt` repository
* RPM based distributions (Fedora, openSUSE, etc) via an `rpm` repository
* Flatpak, via a flatpak remote repository and flatpakref

Arch based distributions can use either the flatpak, or install via the AUR.


# Installation
The following script will attempt to auto-detect your environment and install the correct repository for you.

```bash
curl -fsSL https://beacn-on-linux.github.io/beacn-utility-repo/scripts/install.sh | bash
```

To manually install for a specific distribution, run the following:

## Debian based distributions

```bash
curl -fsSL https://beacn-on-linux.github.io/beacn-utility-repo/scripts/install-deb.sh | bash
```

## RPM based distributions

```bash
curl -fsSL https://beacn-on-linux.github.io/beacn-utility-repo/scripts/install-rpm.sh | bash
```

## Flatpak

```bash
curl -fsSL https://beacn-on-linux.github.io/beacn-utility-repo/scripts/install-flatpak.sh | bash
```
