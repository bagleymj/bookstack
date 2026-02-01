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
            export GEM_HOME="$PWD/.gems"
            export PATH="$GEM_HOME/bin:$PATH"
            export BUNDLE_PATH="$GEM_HOME"

            export PGDATA="$PWD/.postgres"
            export PGHOST="$PWD/.postgres"
            export PGPORT="5432"
            export DATABASE_URL="postgresql://localhost:5432/bookstack_development"

            export TAILWINDCSS_INSTALL_DIR="${pkgs.tailwindcss_4}/bin"
          '';
        };
      }
    );
}
