# Single source of truth for all GitHub Action version pins.
#
# Each entry has:
#   sha — the full commit SHA to pin in workflow files
#   v   — the human-readable version tag (used as trailing comment)
#
# To update: change versions here, then run
#   nix run .#regenerateStandards
# Workflow modules reference these via config.famedly.standards.actionVersions.
{
  # ── Official GitHub Actions ──────────────────────────────────────
  checkout = {
    sha = "de0fac2e4500dabe0009e67214ff5f5447ce83dd";
    v = "v6.0.2";
  };
  cache = {
    sha = "668228422ae6a00e4ad889ee87cd7109ec5666a7";
    v = "v5.0.4";
  };
  uploadArtifact = {
    sha = "bbbca2ddaa5d8feaa63e36b76fdaad77386f024f";
    v = "v7.0.0";
  };
  downloadArtifact = {
    sha = "3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c";
    v = "v8.0.1";
  };
  configurePages = {
    sha = "45bfe0192ca1faeb007ade9deae92b16b8254a0d";
    v = "v6.0.0";
  };
  uploadPagesArtifact = {
    sha = "7b1f4a764d45c48632c6b24a0339c27f5614fb0b";
    v = "v4.0.0";
  };
  deployPages = {
    sha = "cd2ce8fcbc39b97be8ca5fce6e763baed58fa128";
    v = "v5.0.0";
  };
  addToProject = {
    sha = "244f685bbc3b7adfa8466e08b698b5577571133e";
    v = "v1.0.2";
  };

  # ── Docker Actions ───────────────────────────────────────────────
  dockerLogin = {
    sha = "b45d80f862d83dbcd57f89517bcf500b2ab88fb2";
    v = "v4.0.0";
  };
  dockerSetupBuildx = {
    sha = "4d04d5d9486b7bd6fa91e7baf45bbb4f8b9deedd";
    v = "v4.0.0";
  };
  dockerSetupQemu = {
    sha = "ce360397dd3f832beb865e1373c09c0e9f86d70a";
    v = "v4.0.0";
  };
  dockerBuildPush = {
    sha = "d08e5c354a6adb9ed34480a06d141179aa583294";
    v = "v7.0.0";
  };
  dockerMetadata = {
    sha = "030e881283bb7a6894de51c315a6bfe6a94e05cf";
    v = "v6.0.0";
  };
  dockerBake = {
    sha = "82490499d2e5613fcead7e128237ef0b0ea210f7";
    v = "v7.0.0";
  };

  # ── Nix / Cachix ─────────────────────────────────────────────────
  installNix = {
    sha = "51f3067b56fe8ae331890c77d4e454f6d60615ff";
    v = "v31.10.2";
  };
  cachixAction = {
    sha = "1eb2ef646ac0255473d23a5907ad7b04ce94065c";
    v = "v17";
  };

  # ── Code Quality / Security ──────────────────────────────────────
  codecov = {
    sha = "57e3a136b779b570ffcdbf80b3bdc90e7fab3de2";
    v = "v6.0.0";
  };
  claudeCodeAction = {
    sha = "3ac52d0da9f8ec9ca7b4dc23bb477e36ef9c77a9";
    v = "v1.0.79";
  };

  # ── Sequoia PGP ──────────────────────────────────────────────────
  authenticateCommits = {
    sha = "7880c1fe9a32b85ba665e02fb827054a83627a04";
    v = "v1.0.1";
  };
  fastForward = {
    sha = "ea7628bedcb0b0b96e94383ada458d812fca4979";
    v = "v1.0.0";
  };

  # ── Misc ─────────────────────────────────────────────────────────
  famedlyLogin = {
    sha = "465a07811f14bebb1938fbed4728c6a1ff8901fc";
    v = "v2.2.0";
  };
}
