{ pkgs, ... }:

{
  packages = [
    pkgs.beam29Packages.elixir_1_20
    pkgs.postgresql_18
    pkgs.tmux
    pkgs.worktrunk
    pkgs.podman
    pkgs.podman-compose
    pkgs.nixfmt
    pkgs.tailwindcss_4
    pkgs.esbuild
  ]
  ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
    pkgs.inotify-tools
  ];

  env.MIX_TAILWIND_PATH = "${pkgs.tailwindcss_4}/bin/tailwindcss";
  env.MIX_ESBUILD_PATH = "${pkgs.esbuild}/bin/esbuild";
}
