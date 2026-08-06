%{
  configs: [
    %{
      name: "default",
      files: %{included: ["lib/", "test/"], excluded: ["_build/", "deps/"]},
      plugins: [{AshCredo, []}],
      checks: %{
        # TcgCheap.Core is intentionally empty during bootstrap; do not report it.
        disabled: [{AshCredo.Check.Warning.EmptyDomain, []}]
      }
    }
  ]
}
