# My NixOS Configuration

As used for my personal laptop.

## Noteworthy Aspects

- ZFS for all file-systems including the `/` and the `/boot`, giving volume
  management and snapshot backups.

- Mirror ZFS pools on dual SSDs, giving redundancy, fault tolerance, and
  high-performance striped reading.

- Mirror EFI system partitions, allowing booting from either in case one fails.

- Striped dual swap partitions, for high performance.

- Very minimal system state, allowing entire installation to be more easily
  reproduced.

- Script for reproducing the custom drive partitioning, ZFS layout, and NixOS
  installation.

- Organized so that per-machine configuration is separated from general
  configuration.

- Multiple users for different activities, for better security and for tailored
  environments.

- [Companion repository](https://github.com/DerickEddington/dotfiles) that
  provides my "dot files" for users' home directories.

## NixOS Version

These repositories were created using NixOS 21.05 and were very-minorly adjusted
for 21.11 which they now target.

## Installation

Because some of the files in this repository are specific to my particular
laptop, you will need to make some adjustments for your system, as described in
the following steps.  One of the adjustments will be to replace my laptop's
host-name `yoyo` with your own.

Note that this installation guide is somewhat involved and raw and is primarily
intended for rarely setting-up a new personal system only every few years or so
(which is how often I tend to).

### Steps

0. Boot the [NixOS Minimal Live Installer ISO
   Image](https://nixos.org/download.html#nixos-iso) on the machine to install
   to.

---

1. Prepare the live installer system:

   0. Optional: Set a temporary password to be able to SSH into the booted live
      installer system.  In the live system's console, do:
      ```shell
      [nixos@nixos:~]$ passwd
      ```
      Now you can SSH in from another computer, instead of doing the remaining
      steps in the live system's (probably less convenient) console, if you
      like:
      ```shell
      you@another $ ssh nixos@nixos
      ```

   1. Install tools, in the live installer, needed for the remaining steps:
      ```shell
      FAVORITE_EDITOR=emacs-nox  # Or vim, nano, whatever.
      sudo nix-env --install --attr nixos.{git,$FAVORITE_EDITOR}
      ```
      Optional: Whatever else you might like to have. E.g. I also do:
      ```shell
      sudo nix-env --install --attr nixos.most
      export PAGER=most EDITOR=emacs
      ```
---

2. Get this repository and its submodule in the live installer:

   1. ```shell
      git clone --branch github --recurse-submodules \
          https://github.com/DerickEddington/nixos-config.git
      pushd nixos-config
      (cd users/dotfiles
       git checkout github)  # Re-attach the HEAD.
      ```
   2. Optional: Reconfigure repositories to be independent/primary/authoritative
      (not reference GitHub, not have an origin):
      ```shell
      pushd users/dotfiles
      git checkout main
      git branch --delete --force github
      git remote remove origin
      popd
      git checkout main
      git branch --delete --force github
      git remote remove origin
      git submodule deinit users/dotfiles  # Temporary. Step 11 will re-init.
      ```
---

3. Adjust the `nixos-config/.new-installs/prepare-installation` script for your
   system:

   Change some definitions in `prepare-installation`:
   ```shell
   $EDITOR .new-installs/prepare-installation
   ```
   1. Change `INST_NAME` to the host name you want.
   2. Change `DRIVES` elements to the `/dev/disk/by-id/` names of your drives
      that are to be formatted as the mirror zpools to install onto.  (Instead
      of 2 drives, 3 or more, or only 1, should also work fine, if you want that
      many.  If you choose only 1, you must also change `VDEV` to null (but not
      unset).)
   3. Adjust `PARTITION_SIZE` elements as appropriate for the size of your
      drive.  (Note that the mirroring makes the available size that of only a
      single drive.)
   4. If necessary: Adjust `ZPOOL_ASHIFT` for your SSDs' actual physical sector
      size.  (You can read about this elsewhere.)
   5. Adjust `TMP_DATASET_SIZE` and `VM_ZVOL_SIZE` as desired.  (Refer to how
      they are used in the source.)
   6. Optional: Add `/home/$USER` datasets to `MAIN_DATASETS` and
      `MAIN_DATASETS_ORDER` as additional elements, for some/all of your users
      (who will be created later).
   7. Optional: Add extra datasets to `EXTRA_DATASETS` and
      `EXTRA_DATASETS_ORDER` as additional elements, and/or adjust the `VMs`
      ones that are already predefined there, for whatever you might want.

   Stage your changes, for now:
   ```shell
   git add .new-installs/prepare-installation
   ```
   since you might realize you made a mistake and/or should have made some other
   changes, in which case you will need to redo the installation (maybe more
   than once) (which the `prepare-installation` script supports) before it is
   what you want.

   E.g., when I test this guide in a VirtualBox VM, I make changes something
   like:
   ```diff
   --- a/.new-installs/prepare-installation
   +++ b/.new-installs/prepare-installation
   @@ -14,7 +14,7 @@ SELF="$0"
    # Definitions

    # The host name of this installation.
   -INST_NAME=yoyo
   +INST_NAME=tester
    # A reasonably-globally-unique random identifier suffix for the ZFS pool names.
    # Useful because pool names must be unique when imported, and this allows
    # importing multiple pools that have the same "boot" or "main" prefix.
   @@ -28,8 +28,8 @@ done
    [ ${#INST_ID} == 6 ]

    DRIVES=(
   -    /dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_2TB_S59CNM0R706239E
   -    /dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_2TB_S59CNM0R706236Y
   +    /dev/disk/by-id/nvme-eui.c415f365a3935f4da88af47fbc7a08d5
   +    /dev/disk/by-id/nvme-eui.95ec475100e7ce479962f8d26df807cd
    )
    VDEV=mirror

   @@ -72,11 +72,11 @@ declare -A PARTITION_SIZE=(

       #[legacyBIOS]=fixed
               [EFI]=1
   -          [boot]=8
   +          [boot]=4
             #[main]=remaining
   -          [swap]=64
   -    [other-boot]=2
   -    [other-main]=20
   +          [swap]=16
   +    [other-boot]=1
   +    [other-main]=10
    )
    declare -A PARTITION_TYPE_NAME=(
        [legacyBIOS]=biosBoot
   @@ -129,8 +129,8 @@ POOL_PROPS_COMMON=(
    )

    # In GiB
   -TMP_DATASET_SIZE=256
   -VM_ZVOL_SIZE=64
   +TMP_DATASET_SIZE=64
   +VM_ZVOL_SIZE=16

    # These are ordered so that parents are created first, as required.  Those with
    # canmount=off exist only to support being able to inherit properties for all
   @@ -139,6 +139,8 @@ VM_ZVOL_SIZE=64
    MAIN_DATASETS_ORDER=(
        $INST_NAME
        $INST_NAME/home
   +    $INST_NAME/home/me
   +    $INST_NAME/home/work
        $INST_NAME/nix
        $INST_NAME/srv
        $INST_NAME/state
   @@ -156,6 +158,8 @@ MAIN_DATASETS_ORDER=(
    declare -A MAIN_DATASETS=(
        [$INST_NAME]="          -o mountpoint=/"
        [$INST_NAME/home]="     -o devices=off -o setuid=off"
   +    [$INST_NAME/home/me]=""
   +    [$INST_NAME/home/work]="-o quota=128G"
        # Disable atime for faster accesses to the Nix files
        [$INST_NAME/nix]="      -o atime=off"
        [$INST_NAME/srv]=""
   @@ -181,10 +185,14 @@ declare -A BOOT_DATASETS=(
    )

    EXTRA_DATASETS_ORDER=(
   +    old-misc
        VMs
        VMs/blkdev
    )
    declare -A EXTRA_DATASETS=(
   +    [old-misc]="-o mountpoint=/mnt/old-misc -o readonly=on -o compression=zstd \
   +                -o devices=off -o exec=off -o setuid=off"
   +
        # Only used for VM drive images which can either be files which get
        # compressed or zvols which do not.
        [VMs]="-o mountpoint=/mnt/VMs -o compression=zstd \
   @@ -192,7 +200,7 @@ declare -A EXTRA_DATASETS=(
               -o primarycache=metadata -o secondarycache=metadata"
        [VMs/blkdev]="-o canmount=off -o compression=off"
    )
   -for I in {1..8}; do
   +for I in {1..4}; do
        EXTRA_DATASETS_ORDER+=(VMs/blkdev/$I)
        EXTRA_DATASETS[VMs/blkdev/$I]="-V ${VM_ZVOL_SIZE}G -s -b $((2 ** ZPOOL_ASHIFT))"
    done
   ```
---

4. Start running the `prepare-installation` script, as `root`:

   ```shell
   popd
   sudo nixos-config/.new-installs/prepare-installation
   ```

   You must give it some input interactively:
   1. It will generate a unique ID, for your pool names suffix, and ask if you
      want to use it.  If you do not give `yes`, it will generate different ones
      until you accept one, e.g.:
      ```text
      Use INST_ID = acz5zk ? no
      Use INST_ID = g8k5nh ? yes
      ```

   It will print all the commands it does, which is long, and you can ignore
   these unless you want to review them.

   Then it will suspend itself, after printing informative messages about what
   you must do next (which the next step of this guide will direct you to do)
   and about the new layouts, and it will return control to your shell session.
   This will look something like:
   ```text
   Now you must setup /mnt/etc/nixos/per-host/tester/default.nix et al
   to correspond to this new install:

     my.hostName = "tester";
     my.zfs = {
       mirrorDrives = [
         "nvme-eui.c415f365a3935f4da88af47fbc7a08d5"
         "nvme-eui.95ec475100e7ce479962f8d26df807cd"
       ];
       partitions = {
         legacyBIOS = 1;
         EFI        = 2;
         boot       = 3;
         main       = 4;
         swap       = 5;
       };
       pools = let id = "g8k5nh"; in {
         boot.name = "boot-${id}";
         main.name = "main-${id}";
       };
       usersZvolsForVMs = [
         { id = "1"; owner = "${TODO}"; }
         { id = "2"; owner = "${TODO}"; }
         { id = "3"; owner = "${TODO}"; }
         { id = "4"; owner = "${TODO}"; }
       ];
     };

   ... Various print-outs about the new partition and ZFS layouts ...

   Suspending. When the new config is ready, you must resume this script,
   e.g. by using `fg`.

   [1]+  Stopped                 sudo nixos-config/.new-installs/prepare-installation
   ```

   Do not exit this shell session (yet) (otherwise the suspended script will be
   killed and you will have to start over).

---

5. Adjust the new configuration files under `/mnt/etc/nixos/` for your system
   and whatever you want:

   ```shell
   pushd /mnt/etc/nixos
   ```

   1. Adjust `configuration.nix`:
      ```shell
      sudo $EDITOR configuration.nix
      ```
      1. Change `hostName` to the host name you chose (same as `INST_NAME` in
         step 3.1).
      2. Change `users.users` elements to have the users you want, including
         those from your choice in step 3.6 (if any).
      3. Optional: Change anything else you want to be different from my
         choices.  (See the [NixOS documentation](https://nixos.org/learn.html),
         especially [Part
         II. Configuration](https://nixos.org/manual/nixos/stable/index.html#ch-configuration).)

   2. Adjust `zfs.nix`:
      ```shell
      sudo $EDITOR zfs.nix
      ```
      1. Change `fileSystems` elements to match your choices in steps 3.6 and
         3.7 (if any).
      2. Remove my `/mnt/records` dataset (unless you want that).

   3. Adjust `per-host/` to be for your new host:
      ```shell
      NEW_HOSTNAME=...  # The host name you chose.
      sudo git mv per-host/yoyo/default.nix per-host/$NEW_HOSTNAME/
      sudo git rm -r per-host/yoyo
      sudo $EDITOR per-host/$NEW_HOSTNAME/default.nix
      ```
      1. Change `my.hostName` to the host name you chose (same as `hostName` in
         `configuration.nix` in step 5.1.1, which is redundant intentionally).
      2. Change `my.zfs.mirrorDrives` elements to the drives you chose, in the
         same order as you chose (same base-names as `DRIVES` in step 3.2).
      3. Change `my.zfs.pools` to use the pool-names suffix ID you chose (same
         as `INST_ID` in step 4.1).
      4. Change `my.zfs.usersZvolsForVMs` to have equal-or-less-than the amount
         you created (in `EXTRA_DATASETS` in step 3.7) (if any), and change its
         elements to have your desired `owner` users.
      5. Probably: Remove the various aspects that are specific to my system
         that are not relevant to your system, and add aspects that your
         specific system should have.  (Note that you can also make further
         changes after installation, thanks to NixOS.)

   4. Stage your changes, for now:
      ```shell
      sudo git add --all
      ```

   E.g., when I test this guide in a VirtualBox VM, I make changes something
   like:
   ```diff
   --- a/configuration.nix
   +++ b/configuration.nix
   @@ -8,7 +8,7 @@ in

    let
      # Choose for the particular host machine.
   -  hostName = "yoyo";
   +  hostName = "tester";
    in
    {
      imports = [
   @@ -50,10 +50,10 @@ in
          boss = common // {
            extraGroups = [ "wheel" "networkmanager" ];
          };
   -      d = common // {
   +      me = common // {
            extraGroups = [ "audio" ];
          };
   -      z = common;
   +      work = common;
          banking = common;
          bills = common;
        };
   --- a/zfs.nix
   +++ b/zfs.nix
   @@ -257,7 +257,6 @@ in

              (zfsPerHostMountSpecs pools.main ([
                 { mountPoint = "/"; }
   -             { mountPoint = "/mnt/records"; subDataset = "/records"; }
               ]
               ++ (map (mountPoint: { inherit mountPoint; subDataset = mountPoint; }) [
                       "/home"
   @@ -272,12 +271,12 @@ in
                       "/var/local"
                       "/var/log"
                       "/var/tmp"
   -                   "/home/d"
   -                   "/home/z"
   -                   "/home/z/zone"
   +                   "/home/me"
   +                   "/home/work"
               ])))

              (zfsMountSpecs pools.main [
   +            { mountPoint = "/mnt/old-misc"; subDataset = "/old-misc"; }
                { mountPoint = "/mnt/VMs"; subDataset = "/VMs"; }
              ])
   --- a/per-host/yoyo/default.nix
   +++ b/per-host/tester/default.nix
   @@ -31,12 +31,12 @@ in

      # Define this again here to ensure it is checked that this is the same as what
      # /etc/nixos/configuration.nix also defined for the same option.
   -  my.hostName = "yoyo";
   +  my.hostName = "tester";

      my.zfs = {
        mirrorDrives = [  # Names under /dev/disk/by-id/
   -      "nvme-Samsung_SSD_970_EVO_Plus_2TB_S59CNM0R706239E"
   -      "nvme-Samsung_SSD_970_EVO_Plus_2TB_S59CNM0R706236Y"
   +      "nvme-eui.c415f365a3935f4da88af47fbc7a08d5"
   +      "nvme-eui.95ec475100e7ce479962f8d26df807cd"
        ];
        partitions = {
          legacyBIOS = 1;
   @@ -45,15 +45,15 @@ in
          main       = 4;
          swap       = 5;
        };
   -    pools = let id = "7km9ta"; in {
   +    pools = let id = "g8k5nh"; in {
          boot.name = "boot-${id}";
          main.name = "main-${id}";
        };
        usersZvolsForVMs = [
          { id = "1"; owner = "boss"; }
          { id = "2"; owner = "boss"; }
   -      { id = "3"; owner = "z"; }
   -      { id = "4"; owner = "z"; }
   +      { id = "3"; owner = "work"; }
   +      { id = "4"; owner = "work"; }
          # { id = "5"; owner = ; }
          # { id = "6"; owner = ; }
          # { id = "7"; owner = ; }
   ```
   with some unshown further larger removals in
   `per-host/$NEW_HOSTNAME/default.nix`, following step 5.3.5.

---

6. Resume the suspended `prepare-installation` script:

   ```shell
   popd
   fg
   ```

   You must give it some input interactively:

   2. It will ask if you would like to continue installing.  If you give `no`,
      e.g. because you realized something is incorrect or not what you want, it
      will unformat the drives, destroying the ZFS pools and the partitions, and
      abort the installation (allowing you to then fix whatever, rerun
      `prepare-installation`, and redo the steps again).  You might want to do
      `sudo cp -a /mnt/etc/nixos ~nixos/etc-nixos--prev` (or copy that somewhere
      else), so you can refer to your work in that, before giving `no`
      (otherwise that will be destroyed).  If you give `yes`, it will continue
      installing, e.g.:
      ```text
      Continue with installation? yes
      ```

   Then it will install NixOS, according to your `/mnt/etc/nixos`, which could
   take a while.  If it fails, you will need to figure out what was wrong with
   your changes or your execution of the steps, and start over from step 3
   (i.e. you may continue using the same boot-up of the live installer and the
   same clone of the repository, which can be more convenient).

   Then you must give it some input interactively:

   3. It will ask for the password for the `root` user of the new system (which
      you can change or lock later), which will look something like:
      ```text
      Installation finished. No error reported.
      ...
      setting root password...
      New password: 
      ```

   Then it will unmount the new file-systems and export the ZFS pools, and the
   script will finish and return control to your shell session, which will look
   something like:
   ```text
   installation finished!

   Now you may reboot into the newly installed system.
   ```
---

7. Reboot the installee machine and login as `root` via a console:

   0. Do not boot into the live installer.  Boot into the new installation from
      the zpool drives now.
   1. Do not login via the GUI display manager yet (because that would create
      configuration files in a user's home directory but we are not yet ready
      for that).
   2. Switch to a textual console (a "virtual console" in Linux terminology) by
      pressing Ctrl-Alt-F1, and login as `root`.  (VirtualBox tip: The virtual
      "soft keyboard" can be used to "press" Ctrl-Alt-F1.)
   3. Optional: Do not save the next commands in the history:
      ```shell
      unset HISTFILE
      ```
---

8. Optional: Prepare to SSH into the installee machine (which can be more
   convenient, at this point).  As `root`, do:

   1. Edit the NixOS configuration:
      ```shell
      pushd /etc/nixos
      $EDITOR per-host/$HOSTNAME/default.nix
      ```
      Change `services.openssh.enable = true`, e.g:
      ```diff
      --- a/per-host/tester/default.nix
      +++ b/per-host/tester/default.nix
      @@ -133,52 +97,21 @@ in
           # wireless.enable = true;
         };

      -  # services.openssh.enable = true;
      +  services.openssh.enable = true;

         time.timeZone = "America/Los_Angeles";
      ```
   2. Start the SSH server (only temporarily):
      ```shell
      (cd /tmp  # So the created `result` symlink will be here.
       nixos-rebuild test)
      ```
   3. Do not commit this enabling of the SSH server (unless you really want
      to).  Restore the option to be disabled, by discarding that change:
      ```shell
      git restore --patch per-host/$HOSTNAME/default.nix
      popd
      ```
---

9. Login to the installee machine as user `boss` (because this user can use
   `sudo`):
   1. Set the password of `boss`, as `root`:
      ```shell
      passwd boss
      exit
      ```
   2. Login as `boss`, via either:
      - The console; or
      - SSH, if you did step 8:
        ```shell
        you@another $ ssh boss@$NEW_HOSTNAME
        ```
   3. Optional: As `boss`, do not save the next commands in the history:
      ```shell
      unset HISTFILE
      ```
---

10. Set the passwords of your other users that you want to (note that `root` and
    `boss` already had theirs set):

    ```shell
    sudo passwd --lock root  # Optional

    DO_USERS=(me work banking bills)  # Change for your selection.

    for U in ${DO_USERS[@]}; do
      echo -e "\nChoose password for $U:"
      sudo passwd $U
    done
    ```
---

11. Optional: If you did optional step 2.2, re-initialize the
    `/etc/nixos/users/dotfiles` submodule as independent:

    ```shell
    (cd /etc/nixos
     sudo git submodule update --init  # `.git/modules` was already preserved.
     cd users/dotfiles
     sudo git checkout main)

    USERS_DOTFILES_BRANCH=main
    ```

    (Disregard the following warning that occurs, since we want "authoritative
    upstream"):
    ```text
    warning: could not look up configuration 'remote.origin.url'. Assuming this repository is its own authoritative upstream.
    ```
---

12. Adjust Home Manager configuration in `users/dotfiles/.config/nixpkgs/home/`
    to be used by all your users (per-user adjustments will be done later):

    ```shell
    pushd /etc/nixos/users/dotfiles/.config/nixpkgs/home
    ```

    1. Rename to your new host name:
       ```shell
       sudo git mv per-host/{yoyo,$HOSTNAME}
       sudo git mv common/per-host/{yoyo,$HOSTNAME}
       ```

    2. Adjust `common/per-host/`:
       ```shell
       sudo $EDITOR common/per-host/$HOSTNAME/default.nix
       ```
       1. Change `dpi` to the DPI of your monitor/screen/display.

    3. Optional: Change various aspects in the files under
       `.config/nixpkgs/home/` that are my choices which you might want to be
       different.  See the comments in the files.  (Note that you can also make
       further changes later, thanks to Home Manager.)

    ```shell
    popd
    ```
---

13. Optional: Adjust the other configuration files under `users/dotfiles/` for
    all your users:

    ```shell
    pushd /etc/nixos/users/dotfiles
    ```

    - At the top-level, there are some for various utilities.

    - In `.emacs.d/`, there is my Emacs customization.

    (Note that you can also make further changes later, tracked by Git, and pull
    them between users' repositories via the `main` branch of the
    `/etc/nixos/users/dotfiles` origin.)

    ```shell
    popd
    ```
---

14. Commit changes in `/etc/nixos/`:

    1. Starting in `/etc/nixos/users/dotfiles/`:
       ```shell
       pushd /etc/nixos
       pushd users/dotfiles
       sudo git add --all
       sudo git -c user.name=root -c user.email=root@$HOSTNAME \
                commit -m 'Adjustments for new installation.'
       popd
       ```
    2. In `/etc/nixos/` (some changes should already be staged by previous
       steps):
       ```shell
       sudo git add --all
       sudo git -c user.name=root -c user.email=root@$HOSTNAME \
                commit -m 'Adjustments for new installation.'
       popd
       ```
    (Note that the `-c user.name` and `-c user.email` will not be needed again
    after users' configurations are setup.)

---

15. Setup the home directories of your users that you want to:

    1. Run the `setup-home` script as each user in their empty homes (non-empty
       can also be ok, as `root`'s needs to be):
       ```shell
       DO_USERS=(boss root me work banking bills)  # Change for your selection.

       function sudo-u { sudo --user $U --login "$@" ;}

       for U in ${DO_USERS[@]}; do
         echo -e "\n\n\nSetting-up home for user $U ..."
         sudo-u /etc/nixos/users/setup-home

         # Optional: Ensure that the local user name is always used for commits
         # to a user's `~/.dotfiles` repository:
         sudo-u git --git-dir=.dotfiles config user.name $U
         sudo-u git --git-dir=.dotfiles config user.email $U@$HOSTNAME
       done

       unset -f sudo-u
       ```

    2. Setup the `/etc/nixos/users/dotfiles` origin repository to be able to
       pull changes from these users' other branch (`github` or `main`) of their
       repositories (but not their `user/$USER` branch which might need to be
       private):
       ```shell
       pushd /etc/nixos/users/dotfiles
       for U in ${DO_USERS[@]}; do
         if [ $U = root ]; then U_HOME=/root; else U_HOME=/home/$U; fi
         sudo git remote add -t ${USERS_DOTFILES_BRANCH:-github} \
                  user-$U $U_HOME/.dotfiles
       done
       sudo git fetch --all
       popd
       ```
---

16. Optional: Reboot the installee machine, for the sake of it.

    - The SSH server will be disabled now.  (You could do step 8 again to
      temporarily enable it.)

    - You may now login via the GUI display manager.  (You should now have the
      desktop configuration that you chose in steps 12 & 13 (my MATE Desktop
      customization, unless you already changed that).)

---

17. Customize each user's configurations:

    Each user has their own branch, named `user/$USER`, in their `~/.dotfiles`
    clone of the `dotfiles` repository.  Since these branches are not tracked by
    the `/etc/nixos/users/dotfiles` repository (as setup by step 15.2) (which
    does track each user's other branch, to enable sharing), they are private to
    each user, unless you arrange otherwise.

    To use Git with whatever changes you make to a user home, the `~/.dotfiles`
    directory needs to be used as the repository, which is intentionally not
    named `~/.git` to prevent users' homes from being seen as repositories most
    of the time.  You must temporarily make `git` use `~/.dotfiles` when needed:

    - My `with-unhidden-gitdir` command is provided by my `nixos-config`
      repository for this purpose and was installed during the above steps
      (unless you removed it from `environment.systemPackages` in
      `/etc/nixos/configuration.nix`).  It simply temporarily creates a `.git`
      symlink to the repository directory (actually, to the `.git-hidden` that
      references `~/.dotfiles`) during the execution of a given command and then
      deletes the symlink.  E.g.:
      ```shell
      cd ~
      with-unhidden-gitdir git status
      with-unhidden-gitdir emacs  # Then use Magit, VC, etc. in Emacs.
      ```

    - Or, use Git's `--git-dir` or `GIT_DIR` (which do not work well with Magit
      (nor maybe others)):
      ```shell
      git --git-dir=.dotfiles status
      GIT_DIR=.dotfiles git status
      ```

    If changes are made to any of the files under `~/.config/nixpkgs/home/`,
    which are the [Home Manager](https://github.com/nix-community/home-manager)
    configuration (that auto-generates and manages some of a user's
    home-directory files) (already installed by step 15.1), then the
    `home-manager` command will need to be used to apply the changes (and then a
    user might need to logout and then back in, for all changes to take effect).
    E.g.:
    ```shell
    home-manager switch
    ```
    See `man home-manager` and its other
    [documentation](https://nix-community.github.io/home-manager/).

    For example, I might make changes for the `work` user like:
    ```diff
    --- a/.config/nixpkgs/home/default.nix
    +++ b/.config/nixpkgs/home/default.nix
    @@ -23,8 +23,15 @@ in

       # Packages available in per-user profile.
       home.packages = with pkgs; [
    +    rustup
       ];

    +  # Override to use my GitHub identity, for this user.
    +  programs.git = {
    +    userName  = mkForce "Your Name";
    +    userEmail = mkForce "1234567+YourName@users.noreply.github.com";
    +  };
    +
       # Extend the imported options.
       programs.firefox = {
         # profiles = {
    @@ -47,21 +54,21 @@ in

       # Extend the imported options.
       dconf.settings = {
    -    # # More launchers in panel than ./home/common.nix has by default.
    -    # "org/mate/panel/general" = {
    -    #   object-id-list = mkForce [
    -    #     "menu"
    -    #     "web-browser"
    -    #     "music-player"
    -    #     "terminal"
    -    #     "source-code-editor"
    -    #     "window-list"
    -    #     "workspace-switcher"
    -    #     "sys-load-monitor"
    -    #     "indicators"
    -    #     "clock"
    -    #   ];
    -    # };
    +    # More launchers in panel than ./home/common.nix has by default.
    +    "org/mate/panel/general" = {
    +      object-id-list = mkForce [
    +        "menu"
    +        "web-browser"
    +        "music-player"
    +        "terminal"
    +        "source-code-editor"
    +        "window-list"
    +        "workspace-switcher"
    +        "sys-load-monitor"
    +        "indicators"
    +        "clock"
    +      ];
    +    };
       };
    ```

    To note, my provided Home Manager configuration installs the Tree Style Tab
    add-on extension in Firefox (which gives a vertical hierarchical tab bar)
    and also reconfigures the UI a little to work better with this extension
    (mostly, to hide the stock horizontal tab bar).  But this tab bar (nor the
    stock one) is not visible, until you manually do:
    1. Click the `Application Menu` ("hamburger") in the upper right, and choose
       to enable the Tree Style Tab extension.
    2. Click the `View > Sidebar > Tree Style Tab` menu, to actually show the
       tab bar.  (Press the Alt key, to unhide the top menu, if needed.)

    For further changes that you might want to make, the `~/.dotfiles`
    repositories and Home Manager should be helpful for organizing many of your
    changes.

### Redoing After Failure or Mistake

If you have a failure or mistaken choice during installation steps 1 thru 6, it
is generally easy to repeat the steps and make any desired changes, without
rebooting the live installer.  The `prepare-installation` script is able to
reformat the drives and start over fresh.

## Booting With Degraded Drives

If one (or more, if you had 3+) of your drives fails (or is missing), your
system should still be able to boot if there is at least one drive still
functioning.  Note that:

- You might need to enter your UEFI boot manager menu (a.k.a. "BIOS") to choose
  to boot from one of the remaining functioning drives (each has its own
  redundant copy of our bootloader) instead of a default drive.  Some UEFIs
  might not require this because they might automatically choose one of the
  remaining.

- When NixOS starts-up, the importing of the ZFS pools will take a few minutes
  for each of the `main` and `boot` pools because they are degraded, and the
  initialisation of the swap partitions will take a few minutes because some are
  missing.  Altogether, this can take over 5 minutes longer than normal.  It
  should eventually start-up like normal otherwise.

- Once your system is running, you should make a back-up ASAP (which hopefully
  is light, fast, and only incremental because you already had previous back-up
  snapshots).

- You should replace the failed drives, according to the usual ZFS procedures,
  so that your pools are healthy again.

## References

- My approach was derived from that of
  <https://openzfs.github.io/openzfs-docs/Getting%20Started/NixOS/Root%20on%20ZFS.html>,
  but uses a different ZFS dataset layout and a somewhat different partition
  layout.
