defmodule PklElixir.Server do
  @moduledoc """
  GenServer that owns the `pkl server` subprocess and routes messages.

  Communicates with pkl via MessagePack over stdin/stdout. Handles
  request/response correlation for CreateEvaluator and Evaluate calls,
  and dispatches server-initiated requests (ReadModule, ReadResource,
  ListModules, ListResources) to registered reader callbacks.
  """

  use GenServer

  alias PklElixir.{Message, BinaryDecoder, EvalError, InternalError}

  require Logger

  defstruct port: nil,
            buffer: <<>>,
            pending: %{},
            evaluators: %{},
            next_id: 1

  # ── Client API ──────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc """
  Create a new evaluator on the pkl server.

  ## Options

    * `:module_readers` — list of modules implementing `PklElixir.ModuleReader`
    * `:resource_readers` — list of modules implementing `PklElixir.ResourceReader`
    * `:allowed_modules` — list of allowed module URI schemes
    * `:allowed_resources` — list of allowed resource URI schemes
    * `:output_format` — output format (e.g., "json", "yaml")
    * `:module_paths` — list of module paths
    * `:env` — environment variables map
    * `:properties` — properties map
    * `:cache_dir` — cache directory path
    * `:root_dir` — root directory path
    * `:timeout` — timeout in milliseconds (default: 60_000)

  Returns `{:ok, evaluator_id}`.
  """
  def create_evaluator(server, opts \\ []) do
    GenServer.call(server, {:create_evaluator, opts}, timeout(opts))
  end

  @doc "Evaluate a module source. Returns `{:ok, result}` or `{:error, reason}`."
  def evaluate(server, evaluator_id, %PklElixir.ModuleSource{} = source, opts \\ []) do
    GenServer.call(server, {:evaluate, evaluator_id, source, opts}, timeout(opts))
  end

  @doc "Close an evaluator (fire-and-forget)."
  def close_evaluator(server, evaluator_id) do
    GenServer.cast(server, {:close_evaluator, evaluator_id})
  end

  # ── GenServer callbacks ─────────────────────────────────────────────

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:create_evaluator, opts}, from, state) do
    state = ensure_port(state)
    {id, state} = next_id(state)

    # Build reader lookup maps for this evaluator
    module_readers =
      (opts[:module_readers] || [])
      |> Map.new(fn mod -> {mod.scheme(), mod} end)

    resource_readers =
      (opts[:resource_readers] || [])
      |> Map.new(fn mod -> {mod.scheme(), mod} end)

    # Store pending readers so we can register them when we get the evaluator_id
    state = put_in(state.pending[id], {from, module_readers, resource_readers})

    msg = Message.encode_create_evaluator(id, opts)
    Port.command(state.port, msg)
    {:noreply, state}
  end

  def handle_call({:evaluate, evaluator_id, source, opts}, from, state) do
    {id, state} = next_id(state)
    msg = Message.encode_evaluate(id, evaluator_id, source, opts)
    Port.command(state.port, msg)
    {:noreply, %{state | pending: Map.put(state.pending, id, from)}}
  end

  @impl true
  def handle_cast({:close_evaluator, evaluator_id}, state) do
    if state.port do
      msg = Message.encode_close_evaluator(evaluator_id)
      Port.command(state.port, msg)
    end

    {:noreply, %{state | evaluators: Map.delete(state.evaluators, evaluator_id)}}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    process_buffer(%{state | buffer: state.buffer <> data})
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    for {_id, pending} <- state.pending do
      from = extract_from(pending)
      GenServer.reply(from, {:error, %InternalError{message: "pkl server exited with status #{status}"}})
    end

    {:noreply, %{state | port: nil, buffer: <<>>, pending: %{}, evaluators: %{}}}
  end

  def handle_info(msg, state) do
    Logger.debug("pkl_elixir: unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{port: port} = _state) when is_port(port) do
    Port.close(port)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  # ── Buffer processing ───────────────────────────────────────────────

  defp process_buffer(state) do
    case Msgpax.unpack_slice(state.buffer) do
      {:ok, [code, body], rest} when is_integer(code) ->
        state = dispatch(code, body, %{state | buffer: rest})
        process_buffer(state)

      {:ok, _unexpected, rest} ->
        Logger.warning("pkl_elixir: unexpected message format")
        process_buffer(%{state | buffer: rest})

      {:error, _} ->
        # Incomplete message — wait for more data
        {:noreply, state}
    end
  end

  # ── Message dispatch ────────────────────────────────────────────────

  # CreateEvaluatorResponse (0x21)
  defp dispatch(0x21, body, state) do
    request_id = body["requestId"]

    case Map.pop(state.pending, request_id) do
      {nil, _} ->
        Logger.warning("pkl_elixir: no pending request for id=#{request_id}")
        state

      {{from, module_readers, resource_readers}, pending} ->
        state = %{state | pending: pending}

        case body["error"] do
          err when is_binary(err) and err != "" ->
            GenServer.reply(from, {:error, %EvalError{message: err}})
            state

          _ ->
            eval_id = body["evaluatorId"]

            state =
              put_in(state.evaluators[eval_id], %{
                module_readers: module_readers,
                resource_readers: resource_readers
              })

            GenServer.reply(from, {:ok, eval_id})
            state
        end
    end
  end

  # EvaluateResponse (0x24)
  defp dispatch(0x24, body, state) do
    reply_to(body["requestId"], state, fn ->
      case body["error"] do
        err when is_binary(err) and err != "" ->
          {:error, %EvalError{message: err}}

        _ ->
          BinaryDecoder.decode(body["result"])
      end
    end)
  end

  # Log (0x25)
  defp dispatch(0x25, body, state) do
    level = if body["level"] == 0, do: :debug, else: :warning
    Logger.log(level, "[pkl] #{body["message"]}")
    state
  end

  # ReadResource (0x26) — server asks client to read a resource
  defp dispatch(0x26, body, state) do
    handle_reader_request(body, state, :resource_readers, fn reader, uri ->
      reader.read(uri)
    end, &Message.encode_read_resource_response/3)
  end

  # ReadModule (0x28) — server asks client to read a module
  defp dispatch(0x28, body, state) do
    handle_reader_request(body, state, :module_readers, fn reader, uri ->
      reader.read(uri)
    end, &Message.encode_read_module_response/3)
  end

  # ListResources (0x2A) — server asks client to list resources
  defp dispatch(0x2A, body, state) do
    handle_reader_request(body, state, :resource_readers, fn reader, uri ->
      reader.list_elements(uri)
    end, &Message.encode_list_resources_response/3)
  end

  # ListModules (0x2C) — server asks client to list modules
  defp dispatch(0x2C, body, state) do
    handle_reader_request(body, state, :module_readers, fn reader, uri ->
      reader.list_elements(uri)
    end, &Message.encode_list_modules_response/3)
  end

  # Unhandled
  defp dispatch(code, body, state) do
    Logger.warning(
      "pkl_elixir: unhandled message code=0x#{Integer.to_string(code, 16)} body=#{inspect(body)}"
    )

    state
  end

  # ── Server-initiated request handling ───────────────────────────────

  defp handle_reader_request(body, state, reader_type, callback, encode_response) do
    request_id = body["requestId"]
    evaluator_id = body["evaluatorId"]
    uri = body["uri"]
    scheme = scheme_from_uri(uri)

    result =
      case get_in(state.evaluators, [evaluator_id, reader_type, scheme]) do
        nil ->
          {:error, "no #{reader_type} registered for scheme #{inspect(scheme)}"}

        reader ->
          try do
            callback.(reader, uri)
          rescue
            e -> {:error, Exception.message(e)}
          end
      end

    response = encode_response.(request_id, evaluator_id, result)
    Port.command(state.port, response)
    state
  end

  defp scheme_from_uri(uri) when is_binary(uri) do
    case String.split(uri, ":", parts: 2) do
      [scheme, _] -> scheme
      _ -> uri
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  defp reply_to(request_id, state, result_fn) do
    case Map.pop(state.pending, request_id) do
      {nil, _} ->
        Logger.warning("pkl_elixir: no pending request for id=#{request_id}")
        state

      {pending, rest} ->
        from = extract_from(pending)
        GenServer.reply(from, result_fn.())
        %{state | pending: rest}
    end
  end

  # Pending can be either a plain `from` or `{from, module_readers, resource_readers}`
  defp extract_from({from, _mr, _rr}), do: from
  defp extract_from(from), do: from

  defp ensure_port(%{port: nil} = state) do
    pkl = find_pkl!()

    port =
      Port.open({:spawn_executable, pkl}, [
        :binary,
        :exit_status,
        {:args, ["server"]}
      ])

    %{state | port: port}
  end

  defp ensure_port(state), do: state

  defp find_pkl! do
    case System.get_env("PKL_EXEC") do
      nil ->
        System.find_executable("pkl") ||
          raise "pkl executable not found. Install pkl or set PKL_EXEC env var."

      path ->
        path
    end
  end

  defp next_id(%{next_id: id} = state) do
    {id, %{state | next_id: id + 1}}
  end

  defp timeout(opts), do: Keyword.get(opts, :timeout, 60_000)
end
