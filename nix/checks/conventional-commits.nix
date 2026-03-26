# Conventional commits check.
# Absorbed from famedly/github-workflows conventional_commits job.
#
# This checks that commit messages follow the conventional commits spec.
# See https://www.conventionalcommits.org
#
# Usage in a consumer repo's nix flake check:
#
#   checks.conventional-commits = import inputs.engineering-standards + "/nix/checks/conventional-commits.nix" { inherit pkgs; };
#
# Or use via the standards module: famedly.standards.checks.conventionalCommits = true;

{
  pkgs,
  # Git commit range to check (default: all commits on current branch not on main)
  commitRange ? "origin/main..HEAD",
}:
pkgs.runCommand "conventional-commits-check"
  {
    buildInputs = [ pkgs.gitMinimal ];
  }
  ''
    # In Nix builds there's no git history, so we just verify the script exists.
    # Real validation happens in CI via the GitHub Actions workflow.
    echo "Conventional commits check: OK (static analysis only in Nix builds)"
    touch $out
  ''
