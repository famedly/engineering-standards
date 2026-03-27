# Backward-compatibility shims for renamed/moved options.
#
# Uses mkRenamedOptionModule so consumers using the old API get
# automatic migration with deprecation warnings on evaluation.
#
# Migration map:
#   famedly.standards.ci.*                    → famedly.github.workflows.ci.*
#   famedly.standards.workflows.<name>        → famedly.github.workflows.<name>.*
#   famedly.standards.hooks.*                 → famedly.standards.preCommitHooks.*
#   famedly.standards.checks.{enable,reuse}   → famedly.standards.preCommitHooks.*
#   famedly.standards.checks.{typos,typosConfig}  — removed (CI via Nix)
#   famedly.standards.workflows.reuse              — removed (preCommitHooks.fossHooks)

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
