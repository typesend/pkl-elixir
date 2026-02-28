defmodule PklElixir.ModuleReader do
  @moduledoc """
  Behaviour for custom Pkl module readers.

  Implement this behaviour to provide modules from custom URI schemes
  to the Pkl evaluator.

  ## Example

      defmodule MyReader do
        @behaviour PklElixir.ModuleReader

        @impl true
        def scheme, do: "myscheme"

        @impl true
        def is_local, do: false

        @impl true
        def is_globbable, do: false

        @impl true
        def has_hierarchical_uris, do: false

        @impl true
        def read(uri) do
          {:ok, ~S'name = "from custom reader"'}
        end

        @impl true
        def list_elements(_uri), do: {:ok, []}
      end
  """

  @callback scheme() :: String.t()
  @callback is_local() :: boolean()
  @callback is_globbable() :: boolean()
  @callback has_hierarchical_uris() :: boolean()
  @callback read(uri :: String.t()) :: {:ok, String.t()} | {:error, String.t()}
  @callback list_elements(uri :: String.t()) ::
              {:ok, [%{name: String.t(), is_directory: boolean()}]} | {:error, String.t()}
end

defmodule PklElixir.ResourceReader do
  @moduledoc """
  Behaviour for custom Pkl resource readers.

  Implement this behaviour to provide resources from custom URI schemes
  to the Pkl evaluator.

  ## Example

      defmodule MyResourceReader do
        @behaviour PklElixir.ResourceReader

        @impl true
        def scheme, do: "myresource"

        @impl true
        def is_globbable, do: false

        @impl true
        def has_hierarchical_uris, do: false

        @impl true
        def read(uri) do
          {:ok, "resource content bytes"}
        end

        @impl true
        def list_elements(_uri), do: {:ok, []}
      end
  """

  @callback scheme() :: String.t()
  @callback is_globbable() :: boolean()
  @callback has_hierarchical_uris() :: boolean()
  @callback read(uri :: String.t()) :: {:ok, binary()} | {:error, String.t()}
  @callback list_elements(uri :: String.t()) ::
              {:ok, [%{name: String.t(), is_directory: boolean()}]} | {:error, String.t()}
end
