{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.environment.secrets;
  bootCfg = config.boot.secrets;

  secretsLib = pkgs.writeText "nixos-secrets-lib.sh" ''
    # Create temporary gpg homedir
    secrets_gpg_home=$(mktemp -d --tmpdir "nixos-secrets.XXXXXXXX")
    secrets_gpg() {
      '${pkgs.gnupg}/bin/gpg' -q --batch --yes --homedir "$secrets_gpg_home" "$@"
    }

    secrets_cleanup() {
      '${pkgs.gnupg}/bin/gpgconf' --homedir "$secrets_gpg_home" --kill gpg-agent

      rm -r "$secrets_gpg_home"
      unset secrets_gpg_home
      unset -f secrets_gpg
      unset -f secrets_cleanup
    }

    secrets_gpg --import '${config.environment.secretsKey}'
  '';

  decryptBootSecrets = let
    enabledSecrets = attrValues (filterAttrs (n: s: s.enable) bootCfg);
  in pkgs.writers.writeBash "nixos-decrypt-boot-secrets.sh" ''
    set -e
    echo "decrypting boot secrets..."

    source '${secretsLib}'

    mkdir -p /boot/secrets
    chown 0:0 /boot/secrets
    chmod 700 /boot/secrets

    encrypted_secrets=(
      ${concatMapStringsSep "\n" (s: "'${s.source}'") enabledSecrets}
    )
    secrets=(
      ${concatMapStringsSep "\n" (s: "'${s.target}'") enabledSecrets}
    )

    for i in "''${!secrets[@]}"; do
      encrypted_secret="''${encrypted_secrets[i]}"
      secret="/boot/secrets/''${secrets[i]}"
      mkdir -p "$(dirname "$secret")"
      secrets_gpg --decrypt -o "$secret" "$encrypted_secret"
    done

    secrets_cleanup
  '';
in {

  options = {

    environment = {
      secretsKey = mkOption {
        default = "/etc/secrets/key.asc";
        type = types.str;
        description = "Private key used to decrypt secret files.";
      };

      secrets = mkOption {
        default = {};

        type = types.attrsOf (types.submodule ({ name, config, ... }: {
          options = {
            enable = mkOption {
              type = types.bool;
              default = true;
              description = "Whether this secret should be decrypted.";
            };

            target = mkOption {
              type = types.str;
              description = ''
                Name of secret file (relative to <filename>/etc</filename>).
                Defaults to "secrets/&lt;attribute name&gt;".
              '';
            };

            source = mkOption {
              type = types.path;
              description = "Path of the source file.";
            };

            mode = mkOption {
              type = types.str;
              default = "0400";
              example = "0600";
              description = "The mode of the copied secret file.";
            };

            uid = mkOption {
              default = 0;
              type = types.int;
              description = "UID of decrypted secret file.";
            };

            gid = mkOption {
              default = 0;
              type = types.int;
              description = "GID of decrypted secret file.";
            };

            user = mkOption {
              default = "+${toString config.uid}";
              type = types.str;
              description = "User name of decrypted secret file.";
            };

            group = mkOption {
              default = "+${toString config.gid}";
              type = types.str;
              description = "Group name of decrypted secret file.";
            };
          };
          config = {
            target = mkDefault "secrets/${name}";
          };
        }));
      };
    };

    boot.secrets = mkOption {
      default = {};

      type = types.attrsOf (types.submodule ({ name, config, ... }: {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Whether this secret should be decrypted.";
          };

          target = mkOption {
            type = types.str;
            description = ''
              Name of secret file (relative to
              <filename>/boot/secrets</filename>).  Defaults to the attribute
              name.
            '';
          };

          source = mkOption {
            type = types.path;
            description = "Path of the source file.";
          };
        };
        config = {
          target = mkDefault name;
        };
      }));
    };
  };

  config = mkMerge [ (mkIf (cfg != {}) {

    assertions = mapAttrsToList (n: v: {
      assertion = (builtins.match "0[0-7]{3}" v.mode) != null;
      message = "Invalid secret file mode (must be 3 digit octal number)";
    }) cfg;

    environment.etc = mapAttrs (n: v: {
      inherit (v) enable source mode user group target;
    }) cfg;

    system.activationScripts.secrets = stringAfter [ "etc" ] ''
      decrypt_secrets() {
        echo "decrypting secrets..."
        
        source '${secretsLib}'
        local -a secrets=(
          ${concatMapStringsSep "\n" (s: "'${s.target}'") (attrValues (filterAttrs (n: s: s.enable) cfg))}
        )

        for secret in "''${secrets[@]}"; do
          local dec_temp=$(mktemp -p /etc "$secret.XXXXXXXX")

          # Add temporary decrypted secret to list of files to be cleaned up
          echo "$(realpath --relative-to /etc "$dec_temp")" >> /etc/.clean

          # Set umask so gpg does not create a world readable file
          local orig_umask=$(umask)
          umask 0377
          secrets_gpg --decrypt -o "$dec_temp" "/etc/$secret"
          umask $orig_umask

          # Copy permissions of encrypted secret to decrypted file
          chown --reference="/etc/$secret" "$dec_temp"
          chmod --reference="/etc/$secret" "$dec_temp"

          # Move decrypted file over encrypted file
          mv "$dec_temp" "/etc/$secret"

          # Remove temporary file from .clean
          head -n -1 /etc/.clean > /etc/.clean.tmp
          mv /etc/.clean.tmp /etc/.clean
        done

        secrets_cleanup
      }

      decrypt_secrets
    '';
  }) (mkIf (bootCfg != {}) {
     system.extraSystemBuilderCmds = ''
       # Hook the boot secrets script into the switch-to-configuration script
       sed -i '/# Install or update the bootloader./ i system("${decryptBootSecrets}") == 0 or exit 1;' "$out/bin/switch-to-configuration"
     '';

     system.activationScripts.cleanBootSecrets = ''
       rm -rf /boot/secrets/*
     '';
  }) ];
}
