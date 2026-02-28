defmodule PklElixir.ModuleSource do
  @moduledoc """
  Represents a Pkl module to be evaluated.

  A module source has a URI (identifying where it comes from) and
  optionally inline text content.
  """

  @enforce_keys [:uri]
  defstruct [:uri, :text]

  @type t :: %__MODULE__{
          uri: String.t(),
          text: String.t() | nil
        }

  @doc "Create a source from a Pkl text string."
  @spec text(String.t()) :: t()
  def text(content) when is_binary(content) do
    %__MODULE__{uri: "repl:text", text: content}
  end

  @doc "Create a source from a file path."
  @spec file(String.t()) :: t()
  def file(path) when is_binary(path) do
    abs = Path.expand(path)
    %__MODULE__{uri: "file://#{abs}"}
  end

  @doc "Create a source from an arbitrary URI."
  @spec uri(String.t()) :: t()
  def uri(uri) when is_binary(uri) do
    %__MODULE__{uri: uri}
  end
end
