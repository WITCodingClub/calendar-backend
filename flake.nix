{
  description = "WIT Calendar Backend - Rails 8 application";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        ruby = pkgs.ruby_3_4;
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            ruby
            bundler
            postgresql_16
            redis
            nodejs
            yarn
            git
            libffi
            libyaml
            pkg-config
            vips
            poppler_utils
            docker
            docker-compose
          ];

          shellHook = ''
            export BUNDLE_PATH=vendor/bundle
            export RAILS_ENV=development
            echo "WIT Calendar Backend development environment"
            echo "Ruby: $(ruby --version)"
            echo "Bundler: $(bundle --version)"
            echo ""
            echo "Run 'bin/dev' to start the development server"
          '';
        };

        # Docker image builder using Nix
        packages.dockerImage = pkgs.dockerTools.buildLayeredImage {
          name = "ghcr.io/witcodingclub/calendar-backend";
          tag = "latest";

          contents = with pkgs; [
            ruby
            bundler
            postgresql_16
            git
            curl
            bash
            coreutils
          ];

          config = {
            Cmd = [ "${ruby}/bin/ruby" ];
            WorkingDir = "/rails";
            Env = [
              "RAILS_ENV=production"
              "BUNDLE_DEPLOYMENT=1"
              "BUNDLE_PATH=/usr/local/bundle"
            ];
          };
        };
      }
    );
}
