# Recovering From Drive Failure

## Booting With Degraded Drives

If one (or more, if you had 3+) of your drives fails (or is missing), your
system should still be able to boot if there is at least one drive still
functioning.  Note that:

- You might need to enter your UEFI boot manager menu (a.k.a. "BIOS") (or your
  UEFI shell) to choose to boot from one of the remaining functioning drives
  (each has its own redundant copy of our bootloader) instead of a default
  drive.  Some UEFIs might not require this because they might automatically
  choose one of the remaining.

- Unlikely: If all of your EFI-system-partitions are broken (which should not
  happen when at least one drive is still fully functional, and which should
  only happen if you cause some other mistake), there will not be a copy of our
  bootloader, and so your UEFI will not be able to boot it.  But if there still
  are at least one partition of your `boot` pool and one of your `main` pool, it
  should be possible to boot a GRUB2 rescue image (it must have EFI support and
  the `zfs` module) and load your `/boot/grub/grub.cfg` and then boot your
  system.  You can research how to do this elsewhere.

- When NixOS starts-up, the importing of the ZFS pools will take a few minutes
  for each of the `main` and `boot` pools because they are degraded, and the
  initialisation of the swap partitions will take a few minutes because some are
  missing.  Altogether, this can take 5 to 10 minutes longer than normal.  It
  should eventually start-up like normal otherwise.

- If the Stage 1 of the NixOS start-up says
  ```text
  importing root ZFS pool "main-xxxxxx".........................................
  cannot import 'main-xxxxxx': no such pool available
  ```
  but you are sure there is at least one functioning drive, this might need to
  be resolved by moving the functioning drives to the first ports of your
  storage controller (if not already there, taking the place of failed drives
  that were there, of course; which requires physically moving them, for a
  physical machine, of course).  E.g. if you have ports 0,1 and the drive on 0
  failed, then the good drive on 1 will be moved to 0; or if you have ports
  0,1,2,3, and the drives on 0,2 failed, then the good drives on 1,3 will be
  moved to 0,1.  I have seen this issue with VirtualBox and its virtual NVMe SSD
  VDI drives, at least, but not with its IDE nor SATA - this issue might only be
  peculiar to VirtualBox.

- Optional: To avoid the delay with starting-up (if you will not be replacing
  the drives immediately and plan to boot multiple times), it is possible to use
  `zpool detach` manually to remove the bad drives from the pools so that their
  status is no longer "degraded", and also remove the bad drives from
  `my.zfs.mirrorDrives` in `/etc/nixos/per-host/$HOSTNAME/default.nix`, and then
  run `nixos-rebuild`, which should allow the NixOS start-up to be fast like
  normal.  If this is done, the `replace-drives attach` form should be used
  instead, when adding replacement drives as directed by the below section.

## Replacing Drives of Degraded Pools

1. Physically replace the failed drives with new ones that are at least the same
   size as and have the exact same sector size as the good drives that remain.

2. Either: Boot a NixOS live image (e.g. the minimal installer); or, boot your
   system that has degraded drives.  It might be safer to boot a live image,
   which is the only option if you cannot boot your system.

3. Reconfigure your ZFS pools and EFI-system-partitions to use the new drives,
   by using the [companion `replace-drives` script](replace-drives) to do this.
   See its `--help` and read its source, to understand how to use and what it
   will do.  As `root`, do:

   0. If you booted into a NixOS live image, you must do:
      ```shell
      POOL_SUFFIX_ID=...  # Yours. E.g.: "7km9ta".
      zpool import -f -R /mnt main-$POOL_SUFFIX_ID
      zpool import -f -R /mnt boot-$POOL_SUFFIX_ID
      nixos-enter --root /mnt
      ```
      That enters a chroot shell.  Do this and the next steps' commands in it:
      ```shell
      mount --verbose --all  # Bind-mounts /state/etc/{nixos,cryptkey.d}
      USING_NIXOS_ENTER=true
      ```

   1. Use `replace-drives` (in either the chroot shell or your booted system):

      0. Check if any required utilities need to be installed first:
         ```shell
         /etc/nixos/.recovery/replace-drives
         ```
         and if it says something like
         ```text
         which: no sgdisk in (...)
         ...
         ```
         then you must install them all.  E.g.:
         ```shell
         nix-shell -p gptfdisk ...
         ```
      1. See `zpool status -v -P`, `/dev/disk/by-id/*`, and `replace-drives
         --help`, and figure-out what your arguments need to be based on which
         drives are good, bad, and new.  Be careful that what you give is
         correct.

      2. Run `replace-drives` with your arguments.  E.g. something like:
         ```shell
         /etc/nixos/.recovery/replace-drives replace \  # Or "attach"
           --pools 7km9ta \
           --good /dev/disk/by-id/ata-VBOX_HARDDISK_VB9cffc79f-893eef39 \
           --bad-boot 8016453727397922046 \   # Not with "attach"
           --bad-main 14625736125159174971 \  # Not with "attach"
           --new /dev/disk/by-id/ata-VBOX_HARDDISK_VB05d640ec-d141c934
         ```
         It will print what it does, and might pause for a couple minutes (due
         to systemd automount) while attempting to remove the old mount-points
         in `/boot/efis/`, and then it will print a completion message like:
         ```text
          Now you must edit my.zfs.mirrorDrives, in
          /etc/nixos/per-host/$HOSTNAME/default.nix, to
          remove the old replaced drives and add the new replacement drives.  I.e.:

            my.zfs = {
              mirrorDrives = [
                "ata-VBOX_HARDDISK_VB9cffc79f-893eef39"
                "ata-VBOX_HARDDISK_VB05d640ec-d141c934"
              ];
              # ... (The other options should not need changing.)
            };

         Then you must run
           nixos-rebuild boot --install-bootloader $SANDBOXING
         to regenerate the new system configuration so that it uses the new drives and
         not the old.

         Then booting into $HOSTNAME should work normally again.
         ```
      3. Do the directions given by the completion message:
         ```shell
         $EDITOR /etc/nixos/per-host/$HOSTNAME/default.nix  # Change my.zfs.mirrorDrives
         nixos-rebuild boot --install-bootloader ${USING_NIXOS_ENTER:+ --option sandbox false}
         ```

   2. If you booted into a NixOS live image, you must clean-up by doing:
      ```shell
      umount /boot/efis/*
      exit  # Exit the chroot shell.
      ```
      ```shell
      zpool export {boot,main}-$POOL_SUFFIX_ID
      ```

4. Reboot into your system whose pools should now be healthy.
