{ pkgs, ... }:

let
  # nixpkgs still ships Elixir 1.20.4; 1.20.5 carries security fixes and matches
  # the CI and container toolchain. Drop this override once nixpkgs catches up.
  elixir = pkgs.beam29Packages.elixir_1_20.overrideAttrs (_: {
    version = "1.20.5";
    src = pkgs.fetchFromGitHub {
      owner = "elixir-lang";
      repo = "elixir";
      rev = "v1.20.5";
      hash = "sha256-MsRNaWAQ05ysL3hOqpfhm//tRNL0Z4Ia/NfEWEQfEWE=";
    };
  });

  # nixpkgs still ships esbuild 0.27.2; keep the binary aligned with the
  # version configured in config/config.exs for builds outside devenv.
  esbuild = pkgs.esbuild.overrideAttrs (_: {
    version = "0.28.2";
    src = pkgs.fetchFromGitHub {
      owner = "evanw";
      repo = "esbuild";
      rev = "v0.28.2";
      hash = "sha256-I1u+9U5Oj/KzxSjCxwyitwSuDKimatkbC3R2OtaUsfM=";
    };
  });
in
{
  packages = [
    elixir
    pkgs.postgresql_18
    pkgs.tmux
    pkgs.worktrunk
    pkgs.podman
    pkgs.podman-compose
    pkgs.nixfmt
    pkgs.tailwindcss_4
    esbuild
  ]
  ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
    pkgs.inotify-tools
  ];

  env.MIX_TAILWIND_PATH = "${pkgs.tailwindcss_4}/bin/tailwindcss";
  env.MIX_ESBUILD_PATH = "${esbuild}/bin/esbuild";
}
