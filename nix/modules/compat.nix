# Backward-compatibility shims for renamed/moved options.
#
# Uses mkRenamedOptionModule so consumers using the old API get
# automatic migration with deprecation warnings on evaluation.
#
# Migration map:
#   famedly.standards.ci.*                          → famedly.github.workflows.ci.*
#   famedly.standards.workflows.conventionalCommits → famedly.github.workflows.general-checks.enable
#   famedly.standards.workflows.authenticateCommits → famedly.github.workflows.authenticate-commits.enable
#   famedly.standards.workflows.fastForward         → famedly.github.workflows.fast-forward.enable
#   famedly.standards.workflows.addToProject.*      → famedly.github.workflows.add-to-project.*
#   famedly.standards.workflows.updateOpenpgpPolicy.*→ famedly.github.workflows.update-openpgp-policy.*
#   famedly.standards.workflows.aiReview.*          → famedly.github.workflows.ai-review.*
#   famedly.standards.workflows.release.*           → famedly.github.workflows.release.*
#   famedly.standards.workflows.rustCi.*            → famedly.github.workflows.rust-ci.*
#   famedly.standards.workflows.dartCi.*            → famedly.github.workflows.dart-ci.*
#   famedly.standards.workflows.rustPublish.*       → famedly.github.workflows.publish-crate.*
#   famedly.standards.workflows.dartPublish.*       → famedly.github.workflows.publish-pub.*
#   famedly.standards.workflows.dockerBackend.*     → famedly.github.workflows.docker-backend.*
#   famedly.standards.workflows.githubPages.*       → famedly.github.workflows.github-pages.*
#   famedly.standards.hooks.*                       → famedly.standards.preCommitHooks.*
#   famedly.standards.checks.{enable,reuse}         → famedly.standards.preCommitHooks.*
#   famedly.standards.checks.{typos,typosConfig}    — removed (CI via Nix)
#   famedly.standards.workflows.reuse               — removed (preCommitHooks.fossHooks)

{ flake-parts-lib, lib, ... }:
let
  mkDeprecatedOption =
    path: msg:
    { lib, ... }:
    {
      options = lib.setAttrByPath path (
        lib.mkOption {
          type = lib.types.anything;
          default = null;
          visible = false;
          description = "Deprecated: ${msg}";
        }
      );
    };
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { ... }:
    {
      imports =
        let
          std =
            path:
            [
              "famedly"
              "standards"
            ]
            ++ path;
          wf =
            path:
            [
              "famedly"
              "github"
              "workflows"
            ]
            ++ path;
          pch =
            path:
            [
              "famedly"
              "standards"
              "preCommitHooks"
            ]
            ++ path;

          rename = lib.mkRenamedOptionModule;
          deprecated = mkDeprecatedOption;
        in
        [
          # ── CI workflow ────────────────────────────────────────────
          (rename
            (std [
              "ci"
              "enable"
            ])
            (wf [
              "ci"
              "enable"
            ])
          )
          (rename
            (std [
              "ci"
              "armRunners"
            ])
            (wf [
              "ci"
              "armRunners"
            ])
          )

          # ── General / shared workflows ─────────────────────────────
          (rename
            (std [
              "workflows"
              "conventionalCommits"
            ])
            (wf [
              "general-checks"
              "enable"
            ])
          )
          (rename
            (std [
              "workflows"
              "authenticateCommits"
            ])
            (wf [
              "authenticate-commits"
              "enable"
            ])
          )
          (rename
            (std [
              "workflows"
              "fastForward"
            ])
            (wf [
              "fast-forward"
              "enable"
            ])
          )

          # ── Workflows with sub-options ─────────────────────────────
          (rename
            (std [
              "workflows"
              "addToProject"
              "enable"
            ])
            (wf [
              "add-to-project"
              "enable"
            ])
          )
          (rename
            (std [
              "workflows"
              "addToProject"
              "projectUrl"
            ])
            (wf [
              "add-to-project"
              "projectUrl"
            ])
          )
          (rename
            (std [
              "workflows"
              "updateOpenpgpPolicy"
              "enable"
            ])
            (wf [
              "update-openpgp-policy"
              "enable"
            ])
          )
          (rename
            (std [
              "workflows"
              "updateOpenpgpPolicy"
              "teams"
            ])
            (wf [
              "update-openpgp-policy"
              "teams"
            ])
          )
          (rename
            (std [
              "workflows"
              "aiReview"
              "enable"
            ])
            (wf [
              "ai-review"
              "enable"
            ])
          )
          (rename
            (std [
              "workflows"
              "aiReview"
              "model"
            ])
            (wf [
              "ai-review"
              "model"
            ])
          )
          (rename
            (std [
              "workflows"
              "release"
              "enable"
            ])
            (wf [
              "release"
              "enable"
            ])
          )
          (rename
            (std [
              "workflows"
              "release"
              "draft"
            ])
            (wf [
              "release"
              "draft"
            ])
          )

          # ── Hooks → preCommitHooks ─────────────────────────────────
          (rename (std [
            "hooks"
            "enable"
          ]) (pch [ "enable" ]))
          (rename
            (std [
              "hooks"
              "dart"
            ])
            (pch [
              "dartHooks"
              "enable"
            ])
          )
          (rename
            (std [
              "hooks"
              "rust"
            ])
            (pch [
              "rustHooks"
              "enable"
            ])
          )
          (rename
            (std [
              "hooks"
              "python"
            ])
            (pch [
              "pythonHooks"
              "enable"
            ])
          )

          # ── Checks → preCommitHooks ────────────────────────────────
          (rename (std [
            "checks"
            "enable"
          ]) (pch [ "enable" ]))
          (rename
            (std [
              "checks"
              "reuse"
            ])
            (pch [
              "fossHooks"
              "enable"
            ])
          )

          # ── Language CI workflows ───────────────────────────────────
          (rename
            (std [
              "workflows"
              "rustCi"
              "enable"
            ])
            (wf [
              "rust-ci"
              "enable"
            ])
          )
          (rename
            (std [
              "workflows"
              "rustCi"
              "container"
            ])
            (wf [
              "rust-ci"
              "container"
            ])
          )
          (rename
            (std [
              "workflows"
              "rustCi"
              "runner"
            ])
            (wf [
              "rust-ci"
              "runner"
            ])
          )
          (rename
            (std [
              "workflows"
              "rustCi"
              "features"
            ])
            (wf [
              "rust-ci"
              "features"
            ])
          )
          (rename
            (std [
              "workflows"
              "rustCi"
              "coverage"
            ])
            (wf [
              "rust-ci"
              "coverage"
            ])
          )
          (rename
            (std [
              "workflows"
              "rustCi"
              "typos"
            ])
            (wf [
              "rust-ci"
              "typos"
            ])
          )
          (rename
            (std [
              "workflows"
              "rustCi"
              "cargoDeny"
            ])
            (wf [
              "rust-ci"
              "cargoDeny"
            ])
          )
          (rename
            (std [
              "workflows"
              "dartCi"
              "enable"
            ])
            (wf [
              "dart-ci"
              "enable"
            ])
          )
          (rename
            (std [
              "workflows"
              "dartCi"
              "directory"
            ])
            (wf [
              "dart-ci"
              "directory"
            ])
          )
          (rename
            (std [
              "workflows"
              "dartCi"
              "sdk"
            ])
            (wf [
              "dart-ci"
              "sdk"
            ])
          )

          # ── Publishing workflows ─────────────────────────────────────
          (rename
            (std [
              "workflows"
              "rustPublish"
              "enable"
            ])
            (wf [
              "publish-crate"
              "enable"
            ])
          )
          (rename
            (std [
              "workflows"
              "dartPublish"
              "enable"
            ])
            (wf [
              "publish-pub"
              "enable"
            ])
          )

          # ── Docker / deployment workflows ────────────────────────────
          (rename
            (std [
              "workflows"
              "dockerBackend"
              "enable"
            ])
            (wf [
              "docker-backend"
              "enable"
            ])
          )
          (rename
            (std [
              "workflows"
              "dockerBackend"
              "targets"
            ])
            (wf [
              "docker-backend"
              "targets"
            ])
          )
          (rename
            (std [
              "workflows"
              "dockerBackend"
              "oss"
            ])
            (wf [
              "docker-backend"
              "oss"
            ])
          )
          (rename
            (std [
              "workflows"
              "githubPages"
              "enable"
            ])
            (wf [
              "github-pages"
              "enable"
            ])
          )

          # ── Removed (accepted silently with deprecation warning) ───
          (deprecated (std [
            "workflows"
            "reuse"
          ]) "Use preCommitHooks.fossHooks instead.")
          (deprecated (std [
            "checks"
            "typos"
          ]) "Typos checking is now in CI via Nix.")
          (deprecated (std [
            "checks"
            "typosConfig"
          ]) "No longer needed; typos runs in CI via Nix.")
        ];
    }
  );
}
