{ self, nixpkgs, system, ... }:

let
  inherit (nixpkgs) lib;
  pkgs = nixpkgs.legacyPackages.${system};

  makeConfig = modules: lib.nixosSystem {
    inherit system;
    modules = [
      self.nixosModules.microvm
      {
        networking.hostName = "crosvm-platform-test";
        system.stateVersion = "25.11";
        microvm = {
          hypervisor = "crosvm";
          vsock.cid = 77;
        };
      }
    ] ++ modules;
  };

  valid = makeConfig [{
    microvm = {
      crosvm.deviceTreeOverlays = [ "overlay file.dtbo" ];
      devices = [
        {
          bus = "platform";
          path = "6800000.ethernet test";
          crosvm = {
            dtSymbol = "mgbe0";
            mmioBase = 1713569792;
            mapEarly = true;
          };
        }
        {
          bus = "pci";
          path = "0000:01:00.0";
          crosvm.guestAddress = "00:1f.0";
        }
      ];
    };
  }];

  layout = makeConfig [{
    microvm.crosvm = {
      memoryBase = 137438953472;
      platformMmio = {
        base = 1610612736;
        size = 135828340736;
      };
    };
  }];

  runner = import ../lib/runners/crosvm.nix {
    inherit pkgs;
    microvmConfig = valid.config.microvm;
    macvtapFds = { };
    linuxTarget = pkgs.linux.target or pkgs.stdenv.hostPlatform.linux-kernel.target;
  };
  layoutRunner = import ../lib/runners/crosvm.nix {
    inherit pkgs;
    microvmConfig = layout.config.microvm;
    macvtapFds = { };
    linuxTarget = pkgs.linux.target or pkgs.stdenv.hostPlatform.linux-kernel.target;
  };

  assertionsPass = nixos:
    builtins.all ({ assertion, ... }: assertion) nixos.config.assertions;
  missingSymbol = makeConfig [{
    microvm = {
      crosvm.deviceTreeOverlays = [ "overlay.dtbo" ];
      devices = [{ bus = "platform"; path = "6800000.ethernet"; }];
    };
  }];
  missingOverlay = makeConfig [{
    microvm.devices = [{
      bus = "platform";
      path = "6800000.ethernet";
      crosvm.dtSymbol = "mgbe0";
    }];
  }];
  unsupportedHypervisor = makeConfig [{
    microvm = {
      hypervisor = lib.mkForce "qemu";
      crosvm.deviceTreeOverlays = [ "overlay.dtbo" ];
      devices = [{
        bus = "platform";
        path = "6800000.ethernet";
        crosvm.dtSymbol = "mgbe0";
      }];
    };
  }];
  fixedPci = makeConfig [{
    microvm.devices = [{
      bus = "pci";
      path = "0000:01:00.0";
      crosvm.mmioBase = 1713569792;
    }];
  }];
  incompleteLayout = makeConfig [{
    microvm.crosvm.memoryBase = 137438953472;
  }];
  overlappingLayout = makeConfig [{
    microvm = {
      mem = 1024;
      crosvm = {
        memoryBase = 2147483648;
        platformMmio = {
          base = 2147483648;
          size = 4096;
        };
      };
    };
  }];
in
lib.optionalAttrs (lib.hasSuffix "-linux" system) {
  crosvm-platform-devices =
    assert lib.hasInfix "--device-tree-overlay 'overlay file.dtbo'" runner.command;
    assert lib.hasInfix "'/sys/bus/platform/devices/6800000.ethernet test,iommu=off,dt-symbol=mgbe0,mmio-base=1713569792,map-early=true'" runner.command;
    assert lib.hasInfix "/sys/bus/pci/devices/0000:01:00.0,iommu=viommu,guest-address=00:1f.0" runner.command;
    assert assertionsPass valid;
    assert !assertionsPass missingSymbol;
    assert !assertionsPass missingOverlay;
    assert !assertionsPass unsupportedHypervisor;
    assert !assertionsPass fixedPci;
    assert !assertionsPass incompleteLayout;
    assert system != "aarch64-linux" || lib.hasInfix "--mem size=512,base=137438953472" layoutRunner.command;
    assert system != "aarch64-linux" || lib.hasInfix "--platform-mmio base=1610612736,size=135828340736" layoutRunner.command;
    assert system == "aarch64-linux" || !assertionsPass layout;
    assert system != "aarch64-linux" || !assertionsPass overlappingLayout;
    pkgs.runCommand "crosvm-platform-devices" { } "touch $out";
}
