{ pkgs, deploymentName, uuid, args, pluginResources, pluginOptions, baseModules, lib, options, config, ... }: with lib; let
  deploymentInfoModule = rec {
    _file = "module at ${__curPos.file}:${toString __curPos.line}";
    key   = _file;

    deployment = {
      name      = deploymentName;
      arguments = args;
      inherit uuid;
    };
  };

  argsModule = rec {
    _file = "module at ${__curPos.file}:${toString __curPos.line}";
    key   = _file;

    _module.args = {
      inherit (config) resources nodes;
      inherit uuid baseModules;
    };
  };

  nixopsNode = types.submoduleWith ({
    # specialArgs = {
    #   # # TODO: Move these to not special args
    #   # nodes = mapAttrs (_: id) config.nodes;
    #   inherit baseModules;
    # };

    modules = baseModules ++ [
      argsModule
      ({ name, ... }: rec {
        _file = "module at ${__curPos.file}:${toString __curPos.line}";
        key   = _file;
        # Make NixOps's deployment.* options available.
        imports = [ ./options.nix ./resource.nix pluginOptions ];
        # Provide a default hostname and deployment target equal
        # to the attribute name of the machine in the model.
        networking.hostName   = mkOverride 900 name;
        deployment.targetHost = mkOverride 900 name;
        # Must be set for nixops to work on darwin
        nixpkgs.localSystem.system = "x86_64-linux";
        _module.args = { inherit pkgs; };
      })
    ];
  });

in {
  options = with types; {
    defaults = mkOption {
      type    = nixopsNode;
      default = {};
    };

    nodes = mkOption {
      type = attrsOf (submodule (options.defaults.type.functor.payload.modules ++ options.defaults.definitions));
      default = {};
    };

    network = mkOption {
      type    = attrsOf str;
      default = {};
    };

    # resources = mkOption {
    #   type    = attrsOf (attrsOf nixopsResource);
    #   default = {};
    # };

    resources = let
      evalResources = resourceModule: _: mkOption {
        type = attrsOf (submoduleWith {
          modules = [
            argsModule
            resourceModule
            deploymentInfoModule
            ./resource.nix
          ];
        });
        default = {};
      };
    in foldl (a: b: a // (b {
      inherit evalResources;
      zipAttrs = null;
      resourcesByType = null;
    })) {
      sshKeyPairs   = evalResources ./ssh-keypair.nix null;
      commandOutput = evalResources ./command-output.nix null;
      machines      = config.nodes;
    } pluginResources;

    # `require` is special to NixOS modules
    # so we have to use `requires` and switch just before
    # yielding back to nixops
    requires = mkOption {
      type    = listOf (either str path);
      default = [];
    };
  };
}
