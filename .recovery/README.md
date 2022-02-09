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
  missing.  Altogether, this can take 5 to 10 minutes longer than normal (at
  least with VirtualBox).  It should eventually start-up like normal otherwise.

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
  VDI drives, at least - but did not research the problem, and have not tried
  degrading the real drives of my physical laptop - so this issue might only be
  peculiar to VirtualBox.

## Replacing Drives

1. You should physically replace the failed drives (ASAP).

1. Then your ZFS pools and EFI-system-partitions need to be reconfigured to use
   the new drives, by using the [companion `replace-drives`
   script](replace-drives) to do this.  See its `--help` and read its source, to
   understand how to use and what it will do.  This script is designed to also
   work alternatively from a boot of a live-rescue-image (e.g. the NixOS minimal
   installer) (in case you could not boot your system), but after using it you
   must then be able to boot your system (which is hopefully then possible after
   the script made your pools healthy) to manually do the final steps (which the
   script will tell you about).

2. Optional: After the drives were replaced quickly, or if you will not be
   replacing them soon, you should make a back-up ASAP (which hopefully is
   light, fast, and only incremental because you already had previous back-up
   snapshots).
