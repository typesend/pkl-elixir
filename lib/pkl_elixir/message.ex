defmodule PklElixir.Message do
  @moduledoc false

  # Client → Server request codes
  @create_evaluator 0x20
  @close_evaluator 0x22
  @evaluate 0x23

  # Server → Client response/event codes (used in dispatch, not encoding)
  # 0x21 = CreateEvaluatorResponse
  # 0x24 = EvaluateResponse
  # 0x25 = Log

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

  def encode_create_evaluator(request_id, opts \\ []) do
    payload =
      %{"requestId" => request_id}
      |> put_always("allowedModules", opts[:allowed_modules] || @default_allowed_modules)
      |> put_always("allowedResources", opts[:allowed_resources] || @default_allowed_resources)
      |> put_non_nil("outputFormat", opts[:output_format])
      |> put_non_nil("modulePaths", opts[:module_paths])
      |> put_non_nil("env", opts[:env])
      |> put_non_nil("properties", opts[:properties])
      |> put_non_nil("cacheDir", opts[:cache_dir])
      |> put_non_nil("rootDir", opts[:root_dir])

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

  defp pack(term) do
    Msgpax.pack!(term) |> IO.iodata_to_binary()
  end

  defp put_always(map, key, value), do: Map.put(map, key, value)

  defp put_non_nil(map, _key, nil), do: map
  defp put_non_nil(map, key, value), do: Map.put(map, key, value)
end
