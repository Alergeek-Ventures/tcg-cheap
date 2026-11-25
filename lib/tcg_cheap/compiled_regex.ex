defmodule TcgCheap.CompiledRegex do
  @moduledoc """
  Regexes compiled once, for code that runs them for every offer of a batch.

  On Erlang/OTP 28.1+ a regex written in code (`~r` in a function or in a
  module attribute) is stored exported and imported again (`:re.import/1`)
  each time the code evaluating it runs, a few microseconds per pattern (see
  `Regex.import/1`). The offer matchers run dozens of patterns per offer and
  per catalogue product, which made that import a large part of a rematch.

  `get/1` evaluates a function returning a regex, or a structure holding
  regexes, once and keeps the result in `:persistent_term`. The key is the
  function itself, so a recompiled module's function, which is another term,
  compiles its own. It must capture nothing: a variable captured into it would
  make a new key on every call.
  """

  @spec get((-> value)) :: value when value: term()
  def get(compile) when is_function(compile, 0) do
    key = {__MODULE__, compile}

    case :persistent_term.get(key, nil) do
      nil -> store(key, compile)
      compiled -> compiled
    end
  end

  defp store(key, compile) do
    {:env, []} = :erlang.fun_info(compile, :env)
    compiled = compile.()
    :persistent_term.put(key, compiled)
    compiled
  end
end
