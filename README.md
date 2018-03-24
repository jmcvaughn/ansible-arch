# ansible-arch
ansible-arch is a collection of Ansible playbooks and roles that I use to
provision my server, desktop and MacBookAir6,2 (2013, Haswell). Due to the
self-documenting nature of Ansible code, supporting documentation is
intentionally limited, though it may be expanded in the future if time permits
and requirements justify doing so. Users are expected to read and understand the
code and this README; the project has been written with readability in mind. To
use ansible-arch, fork this repository and make the necessary modifications,
using the included variable files as examples. The provided configurations are
for my systems; **you will need to create your own**. See
[Configuration](#configuration) for further information.

Experience with YAML syntax and Ansible prior to running ansible-arch is
assumed; see [Ansible's official
documentation](http://docs.ansible.com/ansible/).

ansible-arch does not perform any user configuration (dotfiles); see
[ansible-dotfiles](https://github.com/v0rn/ansible-dotfiles).

The following sections serve as general guidance in areas that may otherwise not
be clear.

## Pre-requisites
See the [installation guide](INSTALL.md).

## Cloning ansible-arch
To clone this repository and download [pigmonkey's ansible-aur
module](https://github.com/pigmonkey/ansible-aur):
```
$ git clone https://github.com/v0rn/ansible-arch.git && git -C ansible-arch submodule update --init
```

## Configuration
Defaults have been defined in the `defaults/main.yml` file of each that can be
configured. Any valid options that are undefined by default are documented in
these files as comments with examples; thus, consider `defaults/main.yml` for
each role as its documentation. The only exception is the `user` role as all but
the `name` option can be omitted; refer to the `user` role's task to see valid
options for this role.

As general good practice for Ansible, **never** rely on the defaults as anything
more than usage examples; explicitly define all configuration. This prevents
unexpected configuration changes and improves readability by removing the
reliance on these defaults. The only exception is for roles that very obviously
don't apply to a particular host, such as the `nvidia` role for my MacBook Air
and the `macbook` role for my desktop.

As Ansible does not join dictionaries and lists, if you specify a configuration
in your variable files, the entire dictionary for that role must be explicitly
defined. This effectively makes the above good practice mandatory.

### Managing shared and unique role configurations
Systems in the `pc` group share the majority of their configuration. The primary
configuration file for these machines is `group_vars/pc`. For some roles it will
be desirable for some options to be common across the group and some to be
unique to a particular host. Each role uses a single dictionary for
configuration, however [variable precedence rules in
Ansible](http://docs.ansible.com/ansible/playbooks_variables.html#variable-precedence-where-should-i-put-a-variable)
mean that variables will be overridden depending on where they are defined. In
other words, it is not possible to define common configuration options in
a `group_vars/` file and unique configuration in a `host_vars/` file; the former
will be overridden.

The recommended way around this problem is to:
- Define a dictionary for common role configuration in corresponding
  `group_vars/` file appended with `_GROUP`, where `GROUP` is the group name,
  e.g. `wifi_pc`
- Define a dictionary for the unique host configuration in the corresponding
  `host_vars/` file, appended with `_local`, e.g. `wifi_local`
- Combine the above dictionaries into a dictionary matching the role name in the
  `group_vars/` file, e.g. `wifi: '{{ wifi_pc | combine(wifi_local) }}'`

For combining lists a similar principle applies using the `+` operator. Using
the `packages` role as an example:
- In `group_vars/all`: `packages_all.aur: ['cower', 'pacaur']`
- In `group_vars/pc`: `packages_pc.aur: ['telegram-desktop-bin',
  'ideviceinstaller-git']`
- In `group_vars/pc` to combine: `packages.aur: '{{ packages_pc.aur }} + {{
  packages_all.aur }}'`

See `group_vars/pc` for usage examples of both.

## General guidance
### Notebooks
#### tlp
If ansible-arch is run on a notebook, tlp will be installed, enabled and started
with its default settings. `tlp.btrfs_fix` will set `SATA_LINKPWR_ON_BAT` to
`max_performance` if set to `True`, but this is disabled by default as it may
not be necessary (see the [ArchWiki page on
TLP](https://wiki.archlinux.org/index.php/TLP#Btrfs)).

#### MacBooks
The following tasks are performed by the `macbook` role:
- Add udev rules to fix waking with the lid closed
- Copy Xorg configuration for the Apple trackpad
- Enable password-less sudo for adjusting display and keyboard brightness
- For MacBookAir6,2, install xcalib and copy an ICC profile (only for Samsung
  displays but is copied for all MacBookAir6,2 machines).

See the `macbook` role's tasks and `defaults/main.yml` for further details.

### autologin
The `autologin` role enables automatic login to tty1 on boot. This is disabled
by default. **Do not enable this option unless some form of full disk encryption
is in use. Do not enable for headless systems, or systems that aren't using the
i3 role.** The i3 role provides a systemd service that locks the system on
suspend with a blank screen.

### ZFS
ZFS releases may not be in sync with current kernel releases, causing the
installation of ZFS packages to fail. [Check the archzfs repository prior to
running the role.](https://github.com/archzfs/archzfs)

### Docker
The `docker` role only installs Docker and enables/starts `docker.service`.
This is sufficient for my systems as either the `btrfs` or `zfs` Docker storage
drivers will be used automatically. Custom configurations will need to be
applied manually prior to running the role.

### GPG keys
Currently, ansible-arch can add keys automatically. Note that this is not
sensible; automating the addition of keys undermines the point of keys in the
first place. This was done to streamline testing. This will probably be removed
in the future or at the very least some form of interactivity will be
incorporated. Add keys manually following the [ArchWiki guide to adding
unofficial keys for unofficial user
repositories](https://wiki.archlinux.org/index.php/Pacman/Package_signing#Adding_unofficial_keys)
(e.g. for the ZFS repository), or by running the following as your user for AUR
packages (where `KEY` refers to the key to work with):
```
$ gpg --recv-keys KEY         # Receive the key
$ gpg --fingerprint KEY       # Show the key fingerprint so you can verify it yourself
$ gpg --lsign-key KEY         # Locally sign the key to trust
```

### wpa\_supplicant setup
The `wifi` role contains wpa\_supplicant configuration files for my systems,
encrypted using ansible-vault. These files can be ignored or deleted.

wpa\_supplicant is used in conjunction with systemd-networkd and
systemd-resolved. Rename `wpa_supplicant-base.conf` to match your network
interface, and see the [ArchWiki page on
wpa\_supplicant](https://wiki.archlinux.org/index.php/WPA_supplicant) for
configuration and usage. **It is imperative that you encrypt such files using
the ansible-vault utility if you fork this repository; [see Ansible's
documentation on
Vault.](http://docs.ansible.com/ansible/playbooks_vault.html)**

## Usage
As a non-root user, run:
```
$ ansible-playbook pc.yml -i hosts -e host=HOST -K --ask-vault-pass
```

If required, substitute the playbook for your own or `server.yml`. Substitute
`HOST` for the name of the system as defined in the `hosts` file and in the
corresponding `host_vars/` file. `--ask-vault-pass` can be omitted if the
playbook run doesn't use any Vault-encrypted files.

If running the `wifi` role for the first time, reboot the system to apply the
configuration (or unload and reload the appropriate modules and start the
appropriate services).

### Tags
Tags are defined to match role names in the playbooks. It is therefore possible
to limit the executed roles by appending `-t TAG`, where `TAG` refers to a role
or a comma-delimited list of roles to run.

## Known issues
### pacman module (IndexError: list index out of range)
It appears that this error can occur with the pacman Ansible module in at least
the following two circumstances:
- Running the `packages` role for the first time; simply re-run ansible-arch.
- When an alias has been specified for a package, e.g. `libreoffice-fresh-en-gb`
  rather than `libreoffice-fresh-en-GB`. Hopefully this will be fixed in future
  releases, as it would allow a single internationalisation (i18n) setting to be
  used globally.

## Future enhancements (in vague order of priority)
- [ ] Incorporate [iptables](https://wiki.archlinux.org/index.php/iptables) or
  (less likely) [nftables](https://wiki.archlinux.org/index.php/Nftables)
- [ ] Migration to
  [linux-hardened](https://www.archlinux.org/packages/community/x86_64/linux-hardened/)
  with sysctl security tweaks
- [ ] Incorporate [Firejail](https://wiki.archlinux.org/index.php/Firejail)
- [ ] More detailed documentation (wiki)
