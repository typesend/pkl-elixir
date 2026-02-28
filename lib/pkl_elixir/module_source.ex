defmodule PklElixir.ModuleSource do
  @moduledoc false

  @enforce_keys [:uri]
  defstruct [:uri, :text]

  @doc "Create a source from a Pkl text string."
  def text(content) when is_binary(content) do
    %__MODULE__{uri: "repl:text", text: content}
  end

  @doc "Create a source from a file path."
  def file(path) when is_binary(path) do
    abs = Path.expand(path)
    %__MODULE__{uri: "file://#{abs}"}
  end

  @doc "Create a source from an arbitrary URI."
  def uri(uri) when is_binary(uri) do
    %__MODULE__{uri: uri}
  end
end
