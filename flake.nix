{
  description = "Reproducible Cellen backend and Flutter development environment";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        backend = pkgs.python312Packages.buildPythonApplication {
          pname = "cellen-api"; version = "1.0.0"; src = ./.;
          format = "other";
          installPhase = ''mkdir -p $out; cp -r app alembic alembic.ini $out/'';
          propagatedBuildInputs = with pkgs.python312Packages; [
            fastapi uvicorn sqlalchemy alembic asyncpg pydantic pydantic-settings
            python-jose passlib python-multipart aiofiles pillow httpx
          ];
        };
      in {
        packages.backend = backend;
        packages.default = backend;
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ python312 python312Packages.pip postgresql_16 flutter dart git ];
        };
        checks.backend-import = pkgs.runCommand "cellen-backend-import" {
          buildInputs = [ backend ];
        } ''PYTHONPATH=${backend} python -m compileall -q ${backend}/app; touch $out'';
      });
}
