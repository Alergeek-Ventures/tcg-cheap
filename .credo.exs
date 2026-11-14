%{
  configs: [
    %{
      name: "default",
      files: %{included: ["lib/"], excluded: ["_build/", "deps/"]},
      plugins: [{AshCredo, []}]
    }
  ]
}
