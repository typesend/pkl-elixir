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

  ## Custom readers

      defmodule MyReader do
        @behaviour PklElixir.ModuleReader

        @impl true
        def scheme, do: "myapp"
        @impl true
        def is_local, do: false
        @impl true
        def is_globbable, do: false
        @impl true
        def has_hierarchical_uris, do: false

        @impl true
        def read("myapp:" <> path), do: {:ok, "value = 42"}

        @impl true
        def list_elements(_uri), do: {:ok, []}
      end

      PklElixir.evaluate_text(
        ~S'x = import("myapp:config").value',
        module_readers: [MyReader]
      )

  ## Managed lifecycle

  For evaluating multiple modules efficiently, reuse a server:

      {:ok, server} = PklElixir.Server.start_link()
      {:ok, eval_id} = PklElixir.Server.create_evaluator(server)
      {:ok, r1} = PklElixir.Server.evaluate(server, eval_id, PklElixir.ModuleSource.text("x = 1"))
      {:ok, r2} = PklElixir.Server.evaluate(server, eval_id, PklElixir.ModuleSource.text("y = 2"))
      PklElixir.Server.close_evaluator(server, eval_id)
      GenServer.stop(server)

  ## Requirements

  The `pkl` binary must be available. Either install it on PATH or set
  the `PKL_EXEC` environment variable to the path of the pkl executable.
  """

  alias PklElixir.{Server, ModuleSource}

  @doc """
  Evaluate a Pkl file at the given path.

  ## Options

    * `:expr` — evaluate a specific expression instead of the whole module
    * `:module_readers` — list of modules implementing `PklElixir.ModuleReader`
    * `:resource_readers` — list of modules implementing `PklElixir.ResourceReader`
    * `:timeout` — timeout in milliseconds (default: 60_000)

  Returns `{:ok, result}` or `{:error, exception}`.
  """
  @spec evaluate(String.t(), keyword()) :: {:ok, term()} | {:error, Exception.t()}
  def evaluate(path, opts \\ []) when is_binary(path) do
    source = ModuleSource.file(path)
    do_evaluate(source, opts)
  end

  @doc """
  Evaluate Pkl source text directly.

  ## Options

    * `:expr` — evaluate a specific expression instead of the whole module
    * `:module_readers` — list of modules implementing `PklElixir.ModuleReader`
    * `:resource_readers` — list of modules implementing `PklElixir.ResourceReader`
    * `:timeout` — timeout in milliseconds (default: 60_000)

  Returns `{:ok, result}` or `{:error, exception}`.
  """
  @spec evaluate_text(String.t(), keyword()) :: {:ok, term()} | {:error, Exception.t()}
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
