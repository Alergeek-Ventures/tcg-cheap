defmodule Mix.Tasks.Check do
  use Mix.Task

  @moduledoc "Run the project's compact local quality gate."

  @shortdoc "Run the project's quality gate"
  @checks [
    {"format", ["format", "--check-formatted"]},
    {"Ash codegen", ["ash.codegen", "--check"]},
    {"Sobelow", ["sobelow", "--config", "--compact", "--private"]},
    {"compile", ["compile", "--warnings-as-errors"]},
    {"unused dependencies", ["deps.unlock", "--check-unused"]},
    {"xref", ["xref", "graph", "--label", "compile-connected", "--fail-above", "53"]},
    {"Credo", ["credo", "--strict"]},
    {"Dialyzer", ["dialyzer"]}
  ]

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [no_test: :boolean, verbose: :boolean])
    verbose = opts[:verbose] || false

    Enum.each(@checks, fn {label, command} -> run_check(label, command, verbose) end)

    unless opts[:no_test] do
      run_check("tests", ["test"], verbose)
    end
  end

  defp run_check(label, [task | args], verbose) do
    Mix.shell().info("Checking #{label}...")

    {output, status} =
      System.cmd(System.find_executable("mix") || "mix", [task | args], stderr_to_stdout: true)

    if status != 0 do
      Mix.shell().error(output)
      exit(status)
    end

    if verbose and output != "", do: Mix.shell().info(output)
  end
end
