{ pkgs, ... }:

{
  packages = [
    pkgs.ast-grep
    pkgs.gcc
    pkgs.git
    pkgs.jq
    pkgs.nodejs_22
    pkgs.python312
    pkgs.tree-sitter
    pkgs.uv
  ];

  # Keep enterShell quiet so one-shot `devenv shell CMD > report.json`
  # produces machine-readable command output only.
}
