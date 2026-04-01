{
  description = "BookStack - Reading Pipeline Tracker";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Ruby
            ruby_3_3
            bundler

            # Node.js (for asset pipeline)
            nodejs_20
            yarn

            # SQLite
            sqlite

            # Build dependencies
            gcc
            gnumake
            libyaml
            openssl
            zlib
            readline
            libffi
            pkg-config

            # Tailwind CSS (system binary for NixOS compatibility)
            tailwindcss_4

            # File watcher for CSS compilation
            watchman
          ];

          shellHook = ''
            # Resolve the MAIN repo root — immune to worktrees, cd, subshells.
            MAIN_GIT_DIR="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
            if [ -n "$MAIN_GIT_DIR" ] && [ -d "$MAIN_GIT_DIR" ]; then
              BOOKSTACK_ROOT="$(dirname "$MAIN_GIT_DIR")"
            else
              BOOKSTACK_ROOT="$PWD"
            fi

            export GEM_HOME="$BOOKSTACK_ROOT/.gems"
            export PATH="$GEM_HOME/bin:$PATH"
            export BUNDLE_PATH="$GEM_HOME"

            export TAILWINDCSS_INSTALL_DIR="${pkgs.tailwindcss_4}/bin"
          '';
        };
      }
    );
}
