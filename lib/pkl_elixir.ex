defmodule PklElixir do
  @moduledoc """
  Pkl language integration for Elixir.

  Provides an evaluator client that communicates with the `pkl server`
  subprocess via MessagePack over stdin/stdout.

  ## Quick start

      # Evaluate Pkl text
      {:ok, result} = PklElixir.evaluate_text(~S'name = "hello"')
      result["name"]  #=> "hello"

      # Evaluate a .pkl file
      {:ok, result} = PklElixir.evaluate("config.pkl")

      # Evaluate a specific expression
      {:ok, name} = PklElixir.evaluate("config.pkl", expr: "name")
  """

  alias PklElixir.{Server, ModuleSource}

  @doc """
  Evaluate a Pkl file at the given path.

  ## Options

    * `:expr` — evaluate a specific expression instead of the whole module
    * `:timeout` — timeout in milliseconds (default: 60_000)

  Returns `{:ok, result}` or `{:error, exception}`.
  """
  def evaluate(path, opts \\ []) when is_binary(path) do
    source = ModuleSource.file(path)
    do_evaluate(source, opts)
  end

  @doc """
  Evaluate Pkl source text directly.

  ## Options

    * `:expr` — evaluate a specific expression instead of the whole module
    * `:timeout` — timeout in milliseconds (default: 60_000)

  Returns `{:ok, result}` or `{:error, exception}`.
  """
  def evaluate_text(text, opts \\ []) when is_binary(text) do
    source = ModuleSource.text(text)
    do_evaluate(source, opts)
  end

  defp do_evaluate(source, opts) do
    {:ok, server} = Server.start_link()

    try do
      with {:ok, evaluator_id} <- Server.create_evaluator(server, opts),
           result <- Server.evaluate(server, evaluator_id, source, opts) do
        Server.close_evaluator(server, evaluator_id)
        result
      end
    after
      GenServer.stop(server)
    end
  end
end
