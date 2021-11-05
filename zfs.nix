# Created by following:
# https://openzfs.github.io/openzfs-docs/Getting%20Started/NixOS/Root%20on%20ZFS/0-overview.html

{ config, pkgs, lib, ... }:

with builtins;
with lib;
with lists;

let
  allUnique = list: list == unique list;

  driveExists = id: pathExists "/dev/disk/by-id/${id}";

  # My ZFS pool names have a short alpha-numeric unique ID suffix, like: main-1z9h4t
  poolNameRegex = "([[:alpha:]]+)-([[:alnum:]]{6})";
in
{
  options.my.zfs =
    with types;
    let
      driveID = (addCheck str driveExists) // {description = "drive ID";};

      nonEmptyListOfUniqueDriveIDs =
        let type = addCheck (nonEmptyListOf driveID)
                     # Must check driveExists ourself, because listOf.check does
                     # not check its elemType.check.
                     (l: (allUnique l) && (all driveExists l));
        in type // { description = "${type.description} that are unique"; };

      oneOfMirrorDrives =
        let type = addCheck driveID (x: elem x config.my.zfs.mirrorDrives);
        in type // { description = "${type.description} member of mirrorDrives"; };

      partitionNum =
        ints.positive // { description = "drive partition number"; };

      partitionOption = isRequired:
        mkOption (if isRequired
                  then { type = uniq partitionNum; }
                  else { type = uniq (nullOr partitionNum); default = null; });

      poolOptions = {
        name = mkOption { type = uniq (strMatching poolNameRegex); };
        baseDataset = mkOption { type = uniq str; default = ""; };
      };
    in {
      mirrorDrives = mkOption {
        type = uniq nonEmptyListOfUniqueDriveIDs;
      };

      firstDrive = mkOption {
        type = uniq oneOfMirrorDrives;
        default = elemAt config.my.zfs.mirrorDrives 0;
      };

      partitions = {
        legacyBIOS = partitionOption false;
        EFI        = partitionOption true;
        boot       = partitionOption true;
        main       = partitionOption true;
        swap       = partitionOption false;
      };

      pools = {
        boot = poolOptions;
        main = poolOptions;
      };
    };

  config = let
    inherit (config.my) hostName;
    inherit (config.my.zfs) mirrorDrives firstDrive partitions pools;
  in {
    # To avoid infinite recursion, must check these aspects here.
    assertions =
      let
        assertMyZfs = pred: message: { assertion = pred config.my.zfs; inherit message; };

        # Only the boot and main partitions are allowed to be the same, but the
        # others must all be unique.
        uniquePartitions = { partitions, ... }:
          let p = attrsets.filterAttrs (n: v: v != null) partitions;
              distinctPartitionsNums = attrValues (if p.boot == p.main then removeAttrs p ["boot"] else p);
          in allUnique distinctPartitionsNums;

        # The sameness of the boot and main partitions must match the sameness of
        # the boot and main pools.
        samePartitionsAsPools = { partitions, pools, ... }:
          (partitions.boot == partitions.main) == (pools.boot.name == pools.main.name);

        # Pool names must all have the same ID suffix.
        poolsNamesConsistent = { pools, ... }:
          let poolsConfigs = attrValues pools;
              poolsNames = catAttrs "name" poolsConfigs;
              poolsIDs = map (n: elemAt (match poolNameRegex n) 1) poolsNames;
          in length poolsConfigs >= 1 -> length (unique poolsIDs) == 1;

        # If any of the pool configs use the same pool name, then their
        # baseDataset values must be different, else it does not matter.
        uniquePoolsDatasets = { pools, ... }:
          let poolsConfigs = attrValues pools;
          in length (unique poolsConfigs) == length poolsConfigs;
      in [
        (assertMyZfs uniquePartitions
          "my.zfs.partitions must be unique, except for boot and main")
        (assertMyZfs samePartitionsAsPools
          "my.zfs.partitions must match my.zfs.pools")
        (assertMyZfs poolsNamesConsistent
          "my.zfs.pools names must all have the same ID suffix")
        (assertMyZfs uniquePoolsDatasets
          "my.zfs.pools datasets must be unique, when same pool")
      ];

    boot = {
      supportedFilesystems = [ "zfs" ];
      zfs.devNodes = "/dev/disk/by-id";

      loader = {
        grub = {
          enable = true;
          version = 2;
          copyKernels = true;
          efiSupport = true;
          zfsSupport = true;
          devices = map (drive: "/dev/disk/by-id/${drive}") mirrorDrives;
          # for systemd-autofs
          extraPrepareConfig = ''
            mkdir -p /boot/efis
            for i in  /boot/efis/*; do mount $i ; done
          '';
          mirroredBoots =
            map (drive: { devices = [ "/dev/disk/by-id/${drive}" ];
                          efiSysMountPoint = "/boot/efis/${drive}-part${toString partitions.EFI}";
                          path = "/boot"; })
                mirrorDrives;
        };

        efi.efiSysMountPoint = "/boot/efis/${firstDrive}-part${toString partitions.EFI}";

        generationsDir.copyKernels = true;
      };

      # ZFS does not support hibernation and so it must not be done.  (But suspend
      # is safe and allowed.)
      # https://nixos.wiki/wiki/ZFS
      # https://github.com/openzfs/zfs/issues/260
      kernelParams = [ "nohibernate" ];
    };

    environment.etc = {
      "machine-id".source = "/state/etc/machine-id";
      "zfs/zpool.cache".source = "/state/etc/zfs/zpool.cache";
    };

    services.zfs = {
      trim.enable = true;
      autoScrub.enable = true;
    };

    systemd.services.zfs-mount.enable = false;

    fileSystems =
      let
        mountSpecAttr = { mountPoint, device, fsType, options }: {
          name = mountPoint;
          value = { inherit device fsType options; };
        };
        mountSpecs = makeAttr: list: listToAttrs (map makeAttr list);

        zfsMountSpecAttr = poolName: { mountPoint, subDataset }:
          mountSpecAttr {
            inherit mountPoint;
            device = "${poolName}/${hostName}${subDataset}";
            fsType = "zfs"; options = [ "zfsutil" ];
          };
        zfsMountSpecs = poolName: mountSpecs (zfsMountSpecAttr poolName);

        stateBindMountSpecAttr = mountPoint:
          mountSpecAttr {
            inherit mountPoint;
            device = "/state${mountPoint}";
            fsType = "none"; options = [ "bind" ];
          };
        stateBindMountSpecs = mounts: mountSpecs stateBindMountSpecAttr mounts;

        efiMountSpecAttr = drive:
          let drivePart = "${drive}-part${toString partitions.EFI}";
          in mountSpecAttr {
            mountPoint = "/boot/efis/${drivePart}";
            device = "/dev/disk/by-id/${drivePart}";
            fsType = "vfat"; options = [ "x-systemd.idle-timeout=1min" "x-systemd.automount" "noauto" ];
          };
        efiMountSpecs = drives: mountSpecs efiMountSpecAttr drives;
      in
        mkMerge [
          (let bootPool = pools.boot;
           in zfsMountSpecs bootPool.name [
             { mountPoint = "/boot"; subDataset = bootPool.baseDataset; }
           ])

          (let mainPool = pools.main;
           in zfsMountSpecs mainPool.name ([
             { mountPoint = "/"; subDataset = mainPool.baseDataset; }
           ]
           ++ (map (mountPoint: { inherit mountPoint; subDataset = "${mainPool.baseDataset}${mountPoint}"; }) [
                   "/nix"
                   "/srv"
                   "/state"
                   "/tmp"
                   "/usr/local"
                   "/var/cache"
                   "/var/games"
                   "/var/lib"
                   "/var/local"
                   "/var/log"
                   "/var/tmp"
                   # TODO: Will not want to keep this, for users with encrypted home auto-mounted by PAM.
                   "/home/d"
           ])))

          (stateBindMountSpecs [
            "/etc/nixos"
            "/etc/cryptkey.d"
          ])

          (efiMountSpecs mirrorDrives)
        ];

    # TODO: See if can set swapDevices.*.priority to be equal for both.  Would
    #       that result in faster stripping of writes/reads when swap is used?
    swapDevices =
      if partitions.swap != null then
        (map (drive: { device = "/dev/disk/by-id/${drive}-part${toString partitions.swap}";
                       randomEncryption.enable = true; })
             mirrorDrives)
      else [];
  };
}
