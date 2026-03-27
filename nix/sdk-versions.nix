# Central SDK version pins for Dart and Flutter.
#
# These versions are used by both the DevShell (dart.nix) and CI workflows
# (dart-ci.nix) to guarantee identical SDKs locally and in CI.
#
# To update, run: nix run .#updateSdkVersions
#
# Hashes are SHA256 SRI (sha256-<base64>) for official upstream binaries.
{
  dart = {
    version = "3.11.1";
    hashes = {
      x86_64-linux = "sha256-z/uPpK+3d8JjDGYxG/WesDTNPqDH+UrTJuGmLGqpwnI=";
      aarch64-linux = "sha256-F2RclAFLG0ahAOQTW2QjXPnBn5yaP7gUlZroKT816Yw=";
      x86_64-darwin = "sha256-pLTOKT4LZtIysx/E9R9e35MOz1rAc7HvNnco8tH5jS0=";
      aarch64-darwin = "sha256-L/UXrBpAcA9Sv0MJ+2TA3Hqq4cTjiSe9uehoAo1rAvk=";
    };
  };

  # Flutter 3.41.6 — latest stable.
  # Note: Flutter stable does not publish Linux arm64 binaries.
  flutter = {
    version = "3.41.6";
    hashes = {
      x86_64-linux = "sha256-UDs+a301L8pdIbZHTsqVrVRNj8OwU3guq2OjYMf8dWk=";
      x86_64-darwin = "sha256-BuyDNw06ESwn2QN0lD36v4jmVU8hsy5UPQFY7Mdvi68=";
      aarch64-darwin = "sha256-Faccw3Gr5tr7smf0P83ZtL4mxNXl2/SSg6efWNz5By0=";
    };
  };
}
