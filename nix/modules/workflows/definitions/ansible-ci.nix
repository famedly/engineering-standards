{
  config,
  lib,
  inputs,
  workflowsLib,
  famedlyConfig,
  ...
}:
let
  av = famedlyConfig.standards.actionVersions;
  inherit (workflowsLib)
    ghEnv
    ciConcurrency
    nixSetupStep
    mkNixInstallStep
    ;
  nixpkgsRev = inputs.nixpkgs.rev;
in
{
  options.collection = lib.mkOption {
    type = lib.types.str;
    default = "";
    description = "Ansible collection name (e.g. famedly.dns).";
  };

  config.definition = {
    name = "Ansible CI";
    on = {
      push.branches = [ "main" ];
      pullRequest = {
        branches = [ "**" ];
        types = [
          "opened"
          "reopened"
          "synchronize"
        ];
      };
    };
    permissions.contents = "read";
    concurrency = ciConcurrency;
    jobs = {
      lint-roles = {
        name = "Run ansible-lint (roles)";
        runsOn = "ubuntu-latest";
        container = "registry.famedly.net/docker-oss/ansible:py-3.12-ansible-9.0.1";
        defaults.run = {
          shell = "bash";
          workingDirectory = "ansible_collections/${config.collection}";
        };
        steps = [
          {
            name = "Checkout";
            uses = "actions/checkout@${av.checkout}";
            with_ = {
              submodules = "recursive";
              path = "ansible_collections/${config.collection}";
            };
          }
          {
            name = "Prepare env";
            run = ''
              SUBMODULES=$(for path in $(git submodule --quiet foreach pwd); do echo "''${path#"$(pwd)"}/"; done)
              export SUBMODULES
              echo "EXCLUDE=''${SUBMODULES:+--exclude ''${SUBMODULES}}" >> $GITHUB_ENV
            '';
          }
          {
            name = "Install galaxy dependencies";
            run = "find . -iname 'requirements.yml' -exec ansible-galaxy install -r {} \\;";
          }
          {
            name = "Run Ansible Lint";
            run = ''
              ansible-lint \
              --offline \
              --profile safety \
              --skip-list "name[play],name[template],fqcn[action-core],no-tabs" \
              --enable-list "no-handler,no-relative-paths,ignore-errors,meta-incorrect,meta-no-info,meta-no-tags,fqcn" \
              ${ghEnv "EXCLUDE"} roles
            '';
          }
        ];
      };

      lint-playbooks = {
        name = "Run ansible-lint (playbooks)";
        runsOn = "ubuntu-latest";
        container = "registry.famedly.net/docker-oss/ansible:py-3.12-ansible-9.0.1";
        defaults.run = {
          shell = "bash";
          workingDirectory = "ansible_collections/${config.collection}";
        };
        steps = [
          {
            name = "Checkout";
            uses = "actions/checkout@${av.checkout}";
            with_ = {
              submodules = "recursive";
              path = "ansible_collections/${config.collection}";
            };
          }
          {
            name = "Prepare env";
            run = ''
              SUBMODULES=$(for path in $(git submodule --quiet foreach pwd); do echo "''${path#"$(pwd)"}/"; done)
              export SUBMODULES
              echo "EXCLUDE=''${SUBMODULES:+--exclude ''${SUBMODULES}}" >> $GITHUB_ENV
            '';
          }
          {
            name = "Install galaxy dependencies";
            run = "find . -iname 'requirements.yml' -exec ansible-galaxy install -r {} \\;";
          }
          {
            name = "Run Ansible Lint";
            run = ''
              ansible-lint \
              --offline \
              --profile safety \
              --skip-list "name[play],name[template],fqcn[action-core],no-tabs" \
              --enable-list "no-handler,no-relative-paths,ignore-errors,meta-incorrect,meta-no-info,meta-no-tags,fqcn" \
              ${ghEnv "EXCLUDE"} playbooks
            '';
          }
        ];
      };

      test-units = {
        name = "Run unit tests";
        runsOn = "ubuntu-latest";
        container = "registry.famedly.net/docker-oss/ansible:py-3.12-ansible-9.0.1";
        defaults.run = {
          shell = "bash";
          workingDirectory = "ansible_collections/${config.collection}";
        };
        env.TESTING_PATH = "unit";
        steps = [
          {
            name = "Checkout";
            uses = "actions/checkout@${av.checkout}";
            with_ = {
              submodules = "recursive";
              path = "ansible_collections/${config.collection}";
            };
          }
          {
            name = "Prepare env";
            run = ''echo "HAS_TESTS=$([[ -d "tests/unit" ]] && echo true || echo false )" >> $GITHUB_ENV'';
          }
          {
            name = "Run tests";
            if_ = "env.HAS_TESTS == 'true'";
            run = "ansible-test units --coverage";
          }
          {
            name = "Generate coverage report";
            if_ = "env.HAS_TESTS == 'true'";
            run = "ansible-test coverage report\nansible-test coverage xml";
          }
          {
            name = "Upload test artifacts";
            uses = "actions/upload-artifact@${av.uploadArtifact}";
            with_ = {
              name = "ansible-test-unit";
              path = "ansible_collections/${config.collection}/tests/output/";
              if-no-files-found = "ignore";
            };
          }
        ];
      };

      test-sanity = {
        name = "Run sanity tests";
        runsOn = "ubuntu-latest";
        container = "registry.famedly.net/docker-oss/ansible:py-3.12-ansible-9.0.1";
        defaults.run = {
          shell = "bash";
          workingDirectory = "ansible_collections/${config.collection}";
        };
        env.TESTING_PATH = "sanity";
        steps = [
          {
            name = "Checkout";
            uses = "actions/checkout@${av.checkout}";
            with_ = {
              submodules = "recursive";
              path = "ansible_collections/${config.collection}";
            };
          }
          {
            name = "Prepare env";
            run = ''echo "HAS_TESTS=$([[ -d "tests/sanity" ]] && echo true || echo false )" >> $GITHUB_ENV'';
          }
          {
            name = "Run tests";
            if_ = "env.HAS_TESTS == 'true'";
            run = "ansible-test sanity --coverage";
          }
          {
            name = "Generate coverage report";
            if_ = "env.HAS_TESTS == 'true'";
            run = "ansible-test coverage report\nansible-test coverage xml";
          }
          {
            name = "Upload test artifacts";
            uses = "actions/upload-artifact@${av.uploadArtifact}";
            with_ = {
              name = "ansible-test-sanity";
              path = "ansible_collections/${config.collection}/tests/output/";
              if-no-files-found = "ignore";
            };
          }
        ];
      };

      test-integration = {
        name = "Run integration tests";
        runsOn = "ubuntu-latest";
        container = "registry.famedly.net/docker-oss/ansible:py-3.12-ansible-9.0.1";
        defaults.run = {
          shell = "bash";
          workingDirectory = "ansible_collections/${config.collection}";
        };
        env.TESTING_PATH = "integration";
        steps = [
          {
            name = "Checkout";
            uses = "actions/checkout@${av.checkout}";
            with_ = {
              submodules = "recursive";
              path = "ansible_collections/${config.collection}";
            };
          }
          {
            name = "Prepare env";
            run = ''echo "HAS_TESTS=$([[ -d "tests/integration" ]] && echo true || echo false )" >> $GITHUB_ENV'';
          }
          {
            name = "Prepare exclude";
            run = ''
              SUBMODULES=$(for path in $(git submodule --quiet foreach pwd); do echo "''${path#"$(pwd)"}/"; done)
              export SUBMODULES
              echo "EXCLUDE=''${SUBMODULES:+--exclude ''${SUBMODULES}}" >> $GITHUB_ENV
            '';
          }
          {
            name = "Run tests";
            if_ = "env.HAS_TESTS == 'true'";
            run = "ansible-test integration --coverage ${ghEnv "EXCLUDE"}";
          }
          {
            name = "Generate coverage report";
            if_ = "env.HAS_TESTS == 'true'";
            run = "ansible-test coverage report\nansible-test coverage xml";
          }
          {
            name = "Upload test artifacts";
            uses = "actions/upload-artifact@${av.uploadArtifact}";
            with_ = {
              name = "ansible-test-integration";
              path = "ansible_collections/${config.collection}/tests/output/";
              if-no-files-found = "ignore";
            };
          }
        ];
      };

      black = {
        name = "Format using black";
        runsOn = "ubuntu-latest";
        steps = [
          {
            name = "Checkout";
            uses = "actions/checkout@${av.checkout}";
            with_ = {
              submodules = "recursive";
              path = "ansible_collections/${config.collection}";
            };
          }
          (nixSetupStep av.installNix)
          (mkNixInstallStep nixpkgsRev "black")
          {
            name = "Run Black";
            workingDirectory = "ansible_collections/${config.collection}";
            run = "black --check --verbose .";
          }
        ];
      };
    };
  };
}
