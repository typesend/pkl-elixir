defmodule PklElixir.Server do
  @moduledoc """
  GenServer that owns the `pkl server` subprocess and routes messages.

  Communicates with pkl via MessagePack over stdin/stdout. Handles
  request/response correlation for CreateEvaluator and Evaluate calls.
  """

  use GenServer

  alias PklElixir.{Message, BinaryDecoder, EvalError, InternalError}

  require Logger

  defstruct port: nil,
            buffer: <<>>,
            pending: %{},
            next_id: 1

  # ── Client API ──────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc "Create a new evaluator on the pkl server. Returns `{:ok, evaluator_id}`."
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
    msg = Message.encode_create_evaluator(id, opts)
    Port.command(state.port, msg)
    {:noreply, %{state | pending: Map.put(state.pending, id, from)}}
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

    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    process_buffer(%{state | buffer: state.buffer <> data})
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    for {_id, from} <- state.pending do
      GenServer.reply(from, {:error, %InternalError{message: "pkl server exited with status #{status}"}})
    end

    {:noreply, %{state | port: nil, buffer: <<>>, pending: %{}}}
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
    reply_to(body["requestId"], state, fn ->
      case body["error"] do
        err when is_binary(err) and err != "" ->
          {:error, %EvalError{message: err}}

        _ ->
          {:ok, body["evaluatorId"]}
      end
    end)
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

  # Unhandled
  defp dispatch(code, body, state) do
    Logger.warning("pkl_elixir: unhandled message code=0x#{Integer.to_string(code, 16)} body=#{inspect(body)}")
    state
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  defp reply_to(request_id, state, result_fn) do
    case Map.pop(state.pending, request_id) do
      {nil, _} ->
        Logger.warning("pkl_elixir: no pending request for id=#{request_id}")
        state

      {from, pending} ->
        GenServer.reply(from, result_fn.())
        %{state | pending: pending}
    end
  end

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
