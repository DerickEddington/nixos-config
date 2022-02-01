# My NixOS Configuration

As used for my personal laptop.

## Noteworthy Aspects

- ZFS for all file-systems including the `/` and the `/boot`, giving volume
  management and snapshot backups.

- Mirror ZFS pools on dual SSDs, giving redundancy, fault tolerance, and
  high-performance striped reading.

- Mirror EFI system partitions, allowing booting from either in case one fails.

- Striped dual swap partitions, for high performance.

- Very minimal system state, allowing entire installation to be easily
  reproduced.

- Script for reproducing the custom drive partitioning, ZFS layout, and NixOS
  installation.

- Organized so that per-machine configuration is separated from general
  configuration.

- Multiple users for different activities, for better security and for tailored
  environments.

- [Companion repository](https://github.com/DerickEddington/dotfiles) that
  provides my dot-files for users' home directories.
