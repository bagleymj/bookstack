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
          ];

          shellHook = ''
            export GEM_HOME="$PWD/.gems"
            export PATH="$GEM_HOME/bin:$PATH"
            export BUNDLE_PATH="$GEM_HOME"

            # PostgreSQL data directory
            export PGDATA="$PWD/.postgres"
            export PGHOST="$PWD/.postgres"
            export PGPORT="5432"
            export DATABASE_URL="postgresql://localhost:5432/bookstack_development"

            # Initialize PostgreSQL if needed
            if [ ! -d "$PGDATA" ]; then
              echo "Initializing PostgreSQL database..."
              initdb --auth=trust --no-locale --encoding=UTF8
            fi

            # Start PostgreSQL if not running
            if ! pg_ctl status > /dev/null 2>&1; then
              echo "Starting PostgreSQL..."
              pg_ctl start -l "$PGDATA/postgres.log" -o "-k $PGDATA"
              sleep 2
            fi

            # Create the database user and database if they don't exist
            createdb bookstack_development 2>/dev/null || true
            createdb bookstack_test 2>/dev/null || true

            # Install gems if Gemfile exists and Gemfile.lock is missing or outdated
            if [ -f "Gemfile" ]; then
              if [ ! -f "Gemfile.lock" ] || [ "Gemfile" -nt "Gemfile.lock" ]; then
                echo "Installing Ruby gems..."
                bundle install
              fi
            fi

            echo ""
            echo "BookStack development environment ready!"
            echo "Ruby: $(ruby --version)"
            echo "Node: $(node --version)"
            echo "PostgreSQL: $(psql --version)"
            if [ -f "Gemfile.lock" ]; then
              echo "Rails: $(bundle exec rails --version 2>/dev/null || echo 'run bundle install')"
            fi
          '';
        };
      }
    );
}
