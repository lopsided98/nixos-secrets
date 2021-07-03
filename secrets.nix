{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.environment.secrets;
  systemdCfg = config.systemd.secrets;
  bootCfg = config.boot.secrets;

  secretsLib = pkgs.writeText "nixos-secrets-lib.sh" ''
    # Create temporary gpg homedir
    secrets_gpg_home="$('${pkgs.coreutils}/bin/mktemp' -d --tmpdir nixos-secrets.XXXXXXXX)"
    secrets_gpg() {
      '${pkgs.gnupg}/bin/gpg' -q --batch --yes --ignore-time-conflict --homedir "$secrets_gpg_home" "$@"
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
              type = types.str;
              description = "User name of decrypted secret file.";
            };

            group = mkOption {
              type = types.str;
              description = "Group name of decrypted secret file.";
            };
          };
          config = {
            target = mkDefault "secrets/${name}";
            user = mkDefault "+${toString config.uid}";
            group = mkDefault "+${toString config.gid}";
          };
        }));
      };
    };

    systemd.secrets = mkOption {
      type = types.attrsOf (types.submodule ({ name, ... }: {
        options = {
          units = mkOption {
            type = types.listOf types.str;
            description = "Units that require these secrets.";
          };

          lazy = mkOption {
            type = types.bool;
            default = true;
            description = ''
              Whether the secrets should only be decrypted when the unit that
              needs them starts (if true), or at boot (if false).
            '';
          };

          files = mkOption {
            default = {};
            type = types.attrsOf (types.submodule ({ name, config, ... }: {
              options = {
                target = mkOption {
                  type = types.str;
                  description = ''
                    Name of secret file (relative to service runtime directory).
                    Defaults to the attribute name.
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
                  type = types.str;
                  description = "User name of decrypted secret file.";
                };

                group = mkOption {
                  type = types.str;
                  description = "Group name of decrypted secret file.";
                };
              };
              config = {
                target = mkDefault name;
                user = mkDefault "+${toString config.uid}";
                group = mkDefault "+${toString config.gid}";
              };
            }));
          };

          directory = mkOption {
            type = types.path;
            readOnly = true;
            description = ''
              Directory where secrets are stored.
            '';
          };
        };
        config.directory = "/run/" + config.systemd.services."${name}-secrets".serviceConfig.RuntimeDirectory;
      }));
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

  config = mkMerge [
    (mkIf (cfg != {}) {
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
    })

    (mkIf (systemdCfg != {}) {
      assertions = mapAttrsToList (n: { units, ... }: {
        assertion = all (unit: hasAttr unit config.systemd.units) units;
        message = "Invalid systemd unit, one of: ${concatStringsSep ", " units}";
      }) systemdCfg;

      systemd.services = mapAttrs' (name: config: let
        runtimeDirectory = "secrets/${name}";
      in nameValuePair "${name}-secrets" {
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          RuntimeDirectory = runtimeDirectory;
          PrivateTmp = true;
        };
        before = config.units;
        wantedBy = config.units ++ optional (!config.lazy) "multi-user.target";
        script = ''
          set -eu
          source '${secretsLib}'

          decrypt_secret() {
            secret_source="$1"
            secret_target=/run/${escapeShellArg runtimeDirectory}/"$2"
            secret_mode="$3"
            secret_user="$4"
            secret_group="$5"

            mkdir -p "$(dirname "$secret_target")"

            # Set umask so gpg does not create a world readable file
            orig_umask=$(umask)
            umask 0377
            secrets_gpg --decrypt -o "$secret_target" "$secret_source"
            umask $orig_umask

            chown "$secret_user:$secret_group" "$secret_target"
            chmod "$secret_mode" "$secret_target"
          }

          ${concatMapStrings (s: ''
            decrypt_secret ${escapeShellArg "${s.source}"} ${escapeShellArg s.target} ${escapeShellArg s.mode} ${escapeShellArg s.user} ${escapeShellArg s.group}
          '') (attrValues config.files)}

          secrets_cleanup
        '';
      }) systemdCfg;
    })

    (mkIf (bootCfg != {}) {
      system.extraSystemBuilderCmds = ''
        # Hook the boot secrets script into the switch-to-configuration script
        sed -i '/# Install or update the bootloader./ i system("${decryptBootSecrets}") == 0 or exit 1;' "$out/bin/switch-to-configuration"
      '';

      system.activationScripts.cleanBootSecrets = ''
        rm -rf /boot/secrets/*
      '';
    })
  ];
}
