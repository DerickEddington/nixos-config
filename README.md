# My NixOS Configuration

As used for my personal laptop.

## Noteworthy Aspects

- ZFS for all file-systems including the `/` and the `/boot`, giving volume
  management and snapshot backups.

- Mirror ZFS pools on dual (or more) SSDs, giving redundancy, fault tolerance,
  and high-performance striped reading.

- Mirror EFI system partitions, allowing booting from either in case one fails.

- Multiple swap partitions, one per drive, not mirrored, for high-performance
  striped writing and reading.

- Extra support for installing source-code and debug-info, according to your
  choice, for debugging of binaries (executables & libraries) installed by Nix
  packages which don't normally provide this (for both pre-built w/o rebuilding
  or locally-built), and also for arbitrary binaries via dedicated temporary
  directories.  Default installation of the source-code of the system's Glibc
  and Rust std libraries (w/o rebuilding any packages), to help when debugging
  any of the many binaries using those.  Options for NixOS to configure all
  this.

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

These repositories were created using NixOS 21.05 and were minorly adjusted
for 21.11, 22.05, 22.11, 23.05, and then 23.11 which they now target.

## Installation

See [Installation](.new-installs/README.md).

## Recovering From Drive Failure

See [Recovering From Drive Failure](.recovery/README.md).

## References

- My approach was derived from that of
  <https://openzfs.github.io/openzfs-docs/Getting%20Started/NixOS/Root%20on%20ZFS.html>,
  but uses a different ZFS dataset layout and a somewhat different partition
  layout.
