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

            # PostgreSQL
            postgresql_16

            # Build dependencies
            gcc
            gnumake
            libyaml
            openssl
            zlib
            readline
            libffi
            pkg-config

            # For native gem compilation
            libpq

            # Tailwind CSS (system binary for NixOS compatibility)
            tailwindcss_4

            # File watcher for CSS compilation
            watchman
          ];

          shellHook = ''
            # Resolve the MAIN repo root — immune to worktrees, cd, subshells.
            # git rev-parse --git-common-dir always returns the main repo's .git
            # even when evaluated from a worktree. This ensures PGDATA/PGHOST/GEM_HOME
            # always point to the main repo's .postgres/ and .gems/ directories,
            # never to a worktree that lacks them.
            MAIN_GIT_DIR="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
            if [ -n "$MAIN_GIT_DIR" ] && [ -d "$MAIN_GIT_DIR" ]; then
              BOOKSTACK_ROOT="$(dirname "$MAIN_GIT_DIR")"
            else
              BOOKSTACK_ROOT="$PWD"
            fi

            export GEM_HOME="$BOOKSTACK_ROOT/.gems"
            export PATH="$GEM_HOME/bin:$PATH"
            export BUNDLE_PATH="$GEM_HOME"

            export PGDATA="$BOOKSTACK_ROOT/.postgres"
            export PGHOST="$BOOKSTACK_ROOT/.postgres"
            export PGPORT="5432"
            export DATABASE_URL="postgresql://localhost:5432/bookstack_development"

            export TAILWINDCSS_INSTALL_DIR="${pkgs.tailwindcss_4}/bin"
          '';
        };
      }
    );
}
