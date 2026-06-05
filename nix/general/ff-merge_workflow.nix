{ config, ... }:
let
  allowed-actions = config.famedly.standards.allowed-action-versions;
in
{
  perSystem =
    { ... }:
    {
      githubActions.workflows.ff-merge = {
        name = "fast-forward";

        on = {
          issueComment = {
            types = [
              "created"
              "edited"
            ];
          };
        };

        jobs.fast-forward = {
          if_ = "\${{ contains(github.event.comment.body, '/fast-forward') && github.event.issue.pull_request }}";

          runsOn = "ubuntu-latest";

          permissions = {
            contents = "write";
            "pull-requests" = "write";
            issues = "write";
          };

          steps = [
            {
              name = "Fast forwarding";
              uses = allowed-actions."sequoia-pgp/fast-forward".uses;
              with_ = {
                merge = true;
                comment = "on-error";
              };
            }
          ];
        };
      };
    };
}
