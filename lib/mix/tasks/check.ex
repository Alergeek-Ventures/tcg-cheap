defmodule Mix.Tasks.Check do
  use Mix.Task

  @checks [
    {"format", ["format", "--check-formatted"]},
    {"Ash codegen", ["ash.codegen", "--check"]},
    {"Sobelow", ["sobelow", "--config", "--compact", "--private"]},
    {"compile", ["compile", "--warnings-as-errors"]},
    {"unused dependencies", ["deps.unlock", "--check-unused"]},
    {"Credo", ["credo", "--strict"]},
    {"Dialyzer", ["dialyzer"]}
  ]

  @moduledoc """
  Run the project's compact local quality gate.

  Runs every check, even when an earlier one fails, prints the output of each
  failed check and ends with one line naming them. The exit status is non-zero
  when any check failed.

  Checks: #{Enum.map_join(@checks, ", ", &elem(&1, 0))}.

  ## Options

    * `--verbose` - also print the output of passing checks
  """

  @shortdoc "Run the project's quality gate"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [verbose: :boolean])
    verbose = opts[:verbose] || false

    failed =
      for {label, command} <- @checks, not run_check(label, command, verbose), do: label

    if failed != [] do
      Mix.shell().error("Failed checks: #{Enum.join(failed, ", ")}")
      exit({:shutdown, 1})
    end
  end

  defp run_check(label, [task | args], verbose) do
    Mix.shell().info("Checking #{label}...")

    {output, status} =
      System.cmd(System.find_executable("mix") || "mix", [task | args],
        env: [{"MIX_ENV", to_string(Mix.env())}],
        stderr_to_stdout: true
      )

    cond do
      status != 0 -> Mix.shell().error(output)
      verbose and output != "" -> Mix.shell().info(output)
      true -> :ok
    end

    status == 0
  end
end
