# Helpers for the keys of `famedly.standards.dart.projects`, which are paths
# relative to the repository root: `.` for a repository that is one Dart
# project, `./packages/foo` for one that holds several.
{ lib }:
{
  # Prefix for file names inside the project, empty at the repository root.
  directory = project: if project == "." then "" else "${lib.removePrefix "./" project}/";

  # `nix develop` resolves the flake from the working directory, so workflows
  # stay at the repository root and change into the project inside the script.
  inProject =
    project: script:
    if project == "." then script else "cd ${lib.removePrefix "./" project}\n${script}";

  # Workflow and job ids may contain neither `/` nor `.`, so derive a suffix
  # from the project path. Empty at the repository root, which keeps the names
  # of single-project repositories plain.
  suffix =
    project:
    if project == "." then
      ""
    else
      "-${
        lib.replaceStrings
          [
            "./"
            "/"
            "."
          ]
          [
            ""
            "-"
            "-"
          ]
          project
      }";
}
