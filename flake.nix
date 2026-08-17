{
  description = "EchoForge OS (EFOS) — declarative NixOS for the full Cardano ecosystem · All for Simple · est. 2026-04-11";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # 零密钥泄露：所有敏感配置经 Age 加密，解密挂载点 /run/secrets
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # depin (RPi4) 硬件支持
    nixos-hardware.url = "github:NixOS/nixos-hardware";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      sops-nix,
      nixos-hardware,
      ...
    }@inputs:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems =
        f:
        lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              overlays = [ self.overlays.default ];
            }
          )
        );

      mkProfile =
        {
          system,
          profile,
          extraModules ? [ ],
        }:
        lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            {
              nixpkgs.overlays = [ self.overlays.default ];
              nixpkgs.config.allowUnfree = true; # google-chrome
            }
            home-manager.nixosModules.home-manager
            sops-nix.nixosModules.sops
            ./modules
            profile
          ]
          ++ extraModules;
        };
    in
    {
      overlays.default = import ./pkgs/overlay.nix;

      # 四维 Profile 构建入口（CLAUDE.MD §1）
      nixosConfigurations = {
        # 1. 爱好者 / Staking & Browsing：GUI 轻量桌面，节点默认完全关闭
        echoforge-desktop = mkProfile {
          system = "x86_64-linux";
          profile = ./profiles/desktop.nix;
        };

        # 2. 普通开发者 / Smart Contract Sandbox：按需 Local Devnet + Aiken/GHC 工具链
        echoforge-dev = mkProfile {
          system = "x86_64-linux";
          profile = ./profiles/dev.nix;
        };

        # 3. 极客 / Protocol & Full Node：Mithril 快照同步 + 节点监测
        echoforge-spo = mkProfile {
          system = "x86_64-linux";
          profile = ./profiles/spo.nix;
        };

        # 4. DePIN 边缘节点 / RPi4：无头、tmpfs 根、ZRAM、断电自愈（aarch64 交叉目标）
        #    正式部署形态：SSD 按标签分区（echoforge-nix / echoforge-data / echoforge-swap）
        echoforge-depin = mkProfile {
          system = "aarch64-linux";
          profile = ./profiles/depin.nix;
          extraModules = [
            nixos-hardware.nixosModules.raspberry-pi-4
            ./profiles/depin-layout-ssd.nix
          ];
        };

        # 4b. depin 的可烧录 SD 镜像形态：根直接落在 SD 卡（NIXOS_SD），
        #     其余断电自愈策略（ZRAM/watchdog/易失日志）与 4 完全一致。
        #     构建：nix build .#packages.aarch64-linux.depin-sd-image
        echoforge-depin-sd = mkProfile {
          system = "aarch64-linux";
          profile = ./profiles/depin.nix;
          extraModules = [
            nixos-hardware.nixosModules.raspberry-pi-4
            ./profiles/depin-layout-sd.nix
          ];
        };
      };

      packages = forAllSystems (
        pkgs:
        {
          # 全部包均支持 x86_64-linux + aarch64-linux
          # （cardano-node 的 aarch64 静态件来自 Armada Alliance 社区构建）
          inherit (pkgs)
            ef-cli
            cardano-node-bin
            ogmios
            kupo
            mithril-client-bin
            ;
          default = pkgs.ef-cli;
        }
        # depin 可烧录 SD 镜像（zstd 压缩 .img.zst，烧录后首次启动自动扩容根分区）
        // lib.optionalAttrs pkgs.stdenv.hostPlatform.isAarch64 {
          depin-sd-image = self.nixosConfigurations.echoforge-depin-sd.config.system.build.sdImage;
        }
      );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            nixfmt-rfc-style
            sops
            age
            ssh-to-age
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
