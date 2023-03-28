# Created by following:
# https://openzfs.github.io/openzfs-docs/Getting%20Started/NixOS/Root%20on%20ZFS/0-overview.html

{ config, pkgs, lib, ... }:

let
  inherit (builtins)
    all attrNames attrValues catAttrs concatStringsSep elem elemAt
    isAttrs length listToAttrs match pathExists;
  inherit (lib) mkMerge mkOption types;
  inherit (lib.lists) imap1 unique;
  inherit (lib.attrsets) filterAttrs;
in

let
  allUnique = list: list == unique list;

  driveExists = id: pathExists "/dev/disk/by-id/${id}";

  # My ZFS pool names have a short alpha-numeric unique ID suffix, like: main-1z9h4t
  poolNameRegex = "([[:alpha:]]+)-([[:alnum:]]{6})";
  # ZFS dataset names as used by my options must begin with "/" and not end
  # with "/" (and meet the usual ZFS naming requirements), or be the empty
  # string.
  datasetNameRegex = "(/[[:alnum:]][[:alnum:].:_-]*)+|";

  zvolVMsBlkDevExists = id: pathExists "/dev/zvol/${config.my.zfs.pools.main.name}/VMs/blkdev/${id}";

  userExists = userName: elem userName (attrNames config.users.users);
in
{
  options.my.zfs =
    with types;
    let
      driveID = (addCheck str driveExists) // { description = "drive ID"; };

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
        baseDataset = mkOption { type = uniq (strMatching datasetNameRegex); default = ""; };
      };

      zvolVMsBlkDevID = (addCheck str zvolVMsBlkDevExists) // { description = "zvol VMs blkdev ID"; };

      userName = (addCheck str userExists) // { description = "user name"; };
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

      encryptedHomes = {
        noAuto = mkOption {
          type = listOf (either (strMatching datasetNameRegex) (attrsOf str));
          default = [];
        };
      };

      usersZvolsForVMs = mkOption {
        type = listOf (submodule {
          options = {
            id = mkOption {
              type = zvolVMsBlkDevID;
            };
            owner = mkOption {
              type = userName;
            };
          };
        });
        default = [];
      };
    };

  config = let
    inherit (config.my) hostName;
    inherit (config.my.zfs) mirrorDrives firstDrive partitions pools encryptedHomes usersZvolsForVMs;
  in {
    # To avoid infinite recursion, must check these aspects here.
    assertions =
      let
        assertMyZfs = pred: message: { assertion = pred config.my.zfs; inherit message; };

        # Only the boot and main partitions are allowed to be the same, but the
        # others must all be unique.
        uniquePartitions = { partitions, ... }:
          let p = filterAttrs (n: v: v != null) partitions;
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

        # Must not configure a /dev/zvol/${pools.main.name}/VMs/blkdev/${id}
        # more than once.
        uniqueZvolVMsBlkDevIDs = { usersZvolsForVMs, ... }:
          allUnique (map (x: x.id) usersZvolsForVMs);
      in [
        (assertMyZfs uniquePartitions
          "my.zfs.partitions must be unique, except for boot and main")
        (assertMyZfs samePartitionsAsPools
          "my.zfs.partitions must match my.zfs.pools")
        (assertMyZfs poolsNamesConsistent
          "my.zfs.pools names must all have the same ID suffix")
        (assertMyZfs uniquePoolsDatasets
          "my.zfs.pools datasets must be unique, when same pool")
        (assertMyZfs uniqueZvolVMsBlkDevIDs
          "my.zfs.usersZvolsForVMs IDs must be unique")
        {
          assertion =    (map (x: x.devices) config.boot.loader.grub.mirroredBoots)
                      == (map (d: [ "/dev/disk/by-id/${d}" ]) mirrorDrives);
          message = "boot.loader.grub.mirroredBoots does not correspond to only my.zfs.mirrorDrives";
        }
        {
          assertion = config.boot.loader.grub.mirroredBoots != [] -> config.boot.loader.grub.devices == [];
          message = "Should not define both boot.loader.grub.devices and boot.loader.grub.mirroredBoots";
        }
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
          # For systemd-autofs. Designed to not use /etc/fstab (which is no
          # longer valid during drive-replacement recovery).
          extraPrepareConfig = ''
            for D in ${toString mirrorDrives}; do
              DP=$D-part${toString partitions.EFI}
              E=/boot/efis/$DP
              mkdir -p $E
              mount /dev/disk/by-id/$DP $E
            done
          '';
          mirroredBoots =
            imap1 (i: drive: {
              devices = [ "/dev/disk/by-id/${drive}" ];
              efiBootloaderId = "NixOS-${hostName}-drive${toString i}";
              efiSysMountPoint = "/boot/efis/${drive}-part${toString partitions.EFI}";
              path = "/boot";
            }) mirrorDrives;
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

        zfsMountSpecAttr = pool: { mountPoint, subDataset ? "", options ? [] }:
          assert match datasetNameRegex subDataset != null;
          mountSpecAttr {
            inherit mountPoint;
            device = "${pool.name}${pool.baseDataset}${subDataset}";
            fsType = "zfs"; options = [ "zfsutil" ] ++ options;
          };
        zfsMountSpecs = pool: mountSpecs (zfsMountSpecAttr pool);

        zfsPerHostMountSpecAttr = pool: { mountPoint, subDataset ? "", options ? [] }:
          assert match datasetNameRegex subDataset != null;
          zfsMountSpecAttr pool {
            inherit mountPoint options;
            subDataset = "/${hostName}${subDataset}";
          };
        zfsPerHostMountSpecs = pool: mountSpecs (zfsPerHostMountSpecAttr pool);

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

        mkMountSpec = extra @ { ... }: spec: let
          attrs = if isAttrs spec then spec else { mountPoint = spec; subDataset = spec; };
        in extra // attrs;
      in
        mkMerge [
          (zfsPerHostMountSpecs pools.boot [
             { mountPoint = "/boot"; }
           ])

          (zfsPerHostMountSpecs pools.main ([
             { mountPoint = "/"; }
             { mountPoint = "/mnt/archive";             subDataset = "/archive"; }
             { mountPoint = "/mnt/records";             subDataset = "/records"; }
             { mountPoint = "/mnt/omit/home";           subDataset = "/omit/home"; }
             { mountPoint = "/mnt/omit/home/d";         subDataset = "/omit/home/d"; }
             { mountPoint = "/mnt/omit/home/z";         subDataset = "/omit/home/z"; }
           ]
           ++ (map (mkMountSpec {}) [
                   "/home"
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
                   "/home/d"
                   "/home/z"
                   "/home/z/zone"
              ])
           ++ (map (mkMountSpec { options = ["noauto"]; }) ([
              ] ++ encryptedHomes.noAuto))
          ))

          (zfsMountSpecs pools.main [
            { mountPoint = "/mnt/VMs"; subDataset = "/VMs"; }
          ])

          (stateBindMountSpecs [
            "/etc/nixos"
            "/etc/cryptkey.d"
          ])

          (efiMountSpecs mirrorDrives)
        ];

    swapDevices =
      if partitions.swap != null then
        (map (drive: { device = "/dev/disk/by-id/${drive}-part${toString partitions.swap}";
                       priority = 1;
                       randomEncryption.enable = true; })
             mirrorDrives)
      else [];

    services.udev.extraRules = concatStringsSep "\n"
      (map ({ id, owner }:
            ''KERNEL=="zd*" SUBSYSTEM=="block" ACTION=="add|change" '' +
            ''PROGRAM="/run/current-system/sw/lib/udev/zvol_id /dev/%k" '' +
            ''RESULT=="${pools.main.name}/VMs/blkdev/${id}" '' +
            ''OWNER="${owner}"'')
        usersZvolsForVMs);
  };
}
