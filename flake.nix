{
  description = "Neovim inline completion plugin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      pkgsFor = system: import nixpkgs { inherit system; };
    in
    {
      formatter = forAllSystems (system: (pkgsFor system).nixfmt);

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          checkPackages = with pkgs; [
            neovim
            stylua
            lua51Packages.luacheck
          ];
        in
        {
          default = pkgs.mkShell {
            packages = checkPackages;
            LANG = "C";
            LC_ALL = "C";
          };

          ci-check = pkgs.mkShell {
            packages = checkPackages;
            LANG = "C";
            LC_ALL = "C";
          };
        }
      );
    };
}
