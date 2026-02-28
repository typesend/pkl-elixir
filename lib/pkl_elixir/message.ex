defmodule PklElixir.Message do
  @moduledoc false

  # Client → Server request codes
  @create_evaluator 0x20
  @close_evaluator 0x22
  @evaluate 0x23

  # Client → Server response codes (responding to server-initiated requests)
  @read_resource_response 0x27
  @read_module_response 0x29
  @list_resources_response 0x2B
  @list_modules_response 0x2D

  @default_allowed_modules [
    "pkl:",
    "repl:",
    "file:",
    "customfs:",
    "modulepath:",
    "package:",
    "projectpackage:",
    "https:"
  ]

  @default_allowed_resources [
    "env:",
    "prop:",
    "file:",
    "customfs:",
    "modulepath:",
    "package:",
    "projectpackage:",
    "https:"
  ]

  # ── Client requests ─────────────────────────────────────────────────

  def encode_create_evaluator(request_id, opts \\ []) do
    reader_schemes =
      (opts[:module_readers] || [])
      |> Enum.map(fn mod -> mod.scheme() end)

    resource_schemes =
      (opts[:resource_readers] || [])
      |> Enum.map(fn mod -> mod.scheme() end)

    # Merge reader schemes into allowed lists
    allowed_modules = (opts[:allowed_modules] || @default_allowed_modules) ++ Enum.map(reader_schemes, &"#{&1}:")
    allowed_resources = (opts[:allowed_resources] || @default_allowed_resources) ++ Enum.map(resource_schemes, &"#{&1}:")

    payload =
      %{"requestId" => request_id}
      |> put_always("allowedModules", Enum.uniq(allowed_modules))
      |> put_always("allowedResources", Enum.uniq(allowed_resources))
      |> put_non_nil("outputFormat", opts[:output_format])
      |> put_non_nil("modulePaths", opts[:module_paths])
      |> put_non_nil("env", opts[:env])
      |> put_non_nil("properties", opts[:properties])
      |> put_non_nil("cacheDir", opts[:cache_dir])
      |> put_non_nil("rootDir", opts[:root_dir])
      |> put_non_empty("clientModuleReaders", build_module_reader_specs(opts[:module_readers]))
      |> put_non_empty("clientResourceReaders", build_resource_reader_specs(opts[:resource_readers]))

    pack([@create_evaluator, payload])
  end

  def encode_evaluate(request_id, evaluator_id, source, opts \\ []) do
    payload =
      %{
        "requestId" => request_id,
        "evaluatorId" => evaluator_id,
        "moduleUri" => source.uri
      }
      |> put_non_nil("moduleText", source.text)
      |> put_non_nil("expr", opts[:expr])

    pack([@evaluate, payload])
  end

  def encode_close_evaluator(evaluator_id) do
    pack([@close_evaluator, %{"evaluatorId" => evaluator_id}])
  end

  # ── Client responses (to server-initiated requests) ─────────────────

  def encode_read_resource_response(request_id, evaluator_id, {:ok, contents}) do
    pack([
      @read_resource_response,
      %{
        "requestId" => request_id,
        "evaluatorId" => evaluator_id,
        "contents" => Msgpax.Bin.new(contents)
      }
    ])
  end

  def encode_read_resource_response(request_id, evaluator_id, {:error, message}) do
    pack([
      @read_resource_response,
      %{
        "requestId" => request_id,
        "evaluatorId" => evaluator_id,
        "error" => message
      }
    ])
  end

  def encode_read_module_response(request_id, evaluator_id, {:ok, contents}) do
    pack([
      @read_module_response,
      %{
        "requestId" => request_id,
        "evaluatorId" => evaluator_id,
        "contents" => contents
      }
    ])
  end

  def encode_read_module_response(request_id, evaluator_id, {:error, message}) do
    pack([
      @read_module_response,
      %{
        "requestId" => request_id,
        "evaluatorId" => evaluator_id,
        "error" => message
      }
    ])
  end

  def encode_list_resources_response(request_id, evaluator_id, {:ok, elements}) do
    pack([
      @list_resources_response,
      %{
        "requestId" => request_id,
        "evaluatorId" => evaluator_id,
        "pathElements" => Enum.map(elements, &encode_path_element/1)
      }
    ])
  end

  def encode_list_resources_response(request_id, evaluator_id, {:error, message}) do
    pack([
      @list_resources_response,
      %{
        "requestId" => request_id,
        "evaluatorId" => evaluator_id,
        "error" => message
      }
    ])
  end

  def encode_list_modules_response(request_id, evaluator_id, {:ok, elements}) do
    pack([
      @list_modules_response,
      %{
        "requestId" => request_id,
        "evaluatorId" => evaluator_id,
        "pathElements" => Enum.map(elements, &encode_path_element/1)
      }
    ])
  end

  def encode_list_modules_response(request_id, evaluator_id, {:error, message}) do
    pack([
      @list_modules_response,
      %{
        "requestId" => request_id,
        "evaluatorId" => evaluator_id,
        "error" => message
      }
    ])
  end

  # ── Private helpers ─────────────────────────────────────────────────

  defp build_module_reader_specs(nil), do: nil
  defp build_module_reader_specs([]), do: nil

  defp build_module_reader_specs(readers) do
    Enum.map(readers, fn mod ->
      %{
        "scheme" => mod.scheme(),
        "hasHierarchicalUris" => mod.has_hierarchical_uris(),
        "isGlobbable" => mod.is_globbable(),
        "isLocal" => mod.is_local()
      }
    end)
  end

  defp build_resource_reader_specs(nil), do: nil
  defp build_resource_reader_specs([]), do: nil

  defp build_resource_reader_specs(readers) do
    Enum.map(readers, fn mod ->
      %{
        "scheme" => mod.scheme(),
        "hasHierarchicalUris" => mod.has_hierarchical_uris(),
        "isGlobbable" => mod.is_globbable()
      }
    end)
  end

  defp encode_path_element(%{name: name, is_directory: is_dir}) do
    %{"name" => name, "isDirectory" => is_dir}
  end

  defp pack(term) do
    Msgpax.pack!(term) |> IO.iodata_to_binary()
  end

  defp put_always(map, key, value), do: Map.put(map, key, value)

  defp put_non_nil(map, _key, nil), do: map
  defp put_non_nil(map, key, value), do: Map.put(map, key, value)

  defp put_non_empty(map, _key, nil), do: map
  defp put_non_empty(map, _key, []), do: map
  defp put_non_empty(map, key, value), do: Map.put(map, key, value)
end
