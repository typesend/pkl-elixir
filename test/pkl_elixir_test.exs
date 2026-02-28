defmodule PklElixirTest do
  use ExUnit.Case

  alias PklElixir.{BinaryDecoder, ModuleSource, Message}

  # ── Binary Decoder ───────────────────────────────────────────────────

  describe "BinaryDecoder" do
    test "decodes nil" do
      assert {:ok, nil} = BinaryDecoder.decode(nil)
      assert {:ok, nil} = BinaryDecoder.decode(<<>>)
    end

    test "decodes primitives" do
      assert {:ok, "hello"} = BinaryDecoder.decode(Msgpax.pack!("hello") |> IO.iodata_to_binary())
      assert {:ok, 42} = BinaryDecoder.decode(Msgpax.pack!(42) |> IO.iodata_to_binary())
      assert {:ok, 3.14} = BinaryDecoder.decode(Msgpax.pack!(3.14) |> IO.iodata_to_binary())
      assert {:ok, true} = BinaryDecoder.decode(Msgpax.pack!(true) |> IO.iodata_to_binary())
      assert {:ok, false} = BinaryDecoder.decode(Msgpax.pack!(false) |> IO.iodata_to_binary())
      assert {:ok, nil} = BinaryDecoder.decode(Msgpax.pack!(nil) |> IO.iodata_to_binary())
    end

    test "decodes object with properties" do
      # Object: [0x01, class_name, module_uri, [members...]]
      object = [0x01, "MyClass", "repl:text", [[0x10, "name", "hello"], [0x10, "age", 30]]]
      bytes = Msgpax.pack!(object) |> IO.iodata_to_binary()

      assert {:ok, %{"name" => "hello", "age" => 30}} = BinaryDecoder.decode(bytes)
    end

    test "decodes object with nested objects" do
      inner = [0x01, "Inner", "repl:text", [[0x10, "x", 1]]]
      outer = [0x01, "Outer", "repl:text", [[0x10, "nested", inner]]]
      bytes = Msgpax.pack!(outer) |> IO.iodata_to_binary()

      assert {:ok, %{"nested" => %{"x" => 1}}} = BinaryDecoder.decode(bytes)
    end

    test "decodes list type" do
      list = [0x04, [1, 2, 3]]
      bytes = Msgpax.pack!(list) |> IO.iodata_to_binary()

      assert {:ok, [1, 2, 3]} = BinaryDecoder.decode(bytes)
    end

    test "decodes duration" do
      dur = [0x07, 5.0, "min"]
      bytes = Msgpax.pack!(dur) |> IO.iodata_to_binary()

      assert {:ok, %{value: 5.0, unit: "min"}} = BinaryDecoder.decode(bytes)
    end

    test "decodes pair as tuple" do
      pair = [0x09, "key", "value"]
      bytes = Msgpax.pack!(pair) |> IO.iodata_to_binary()

      assert {:ok, {"key", "value"}} = BinaryDecoder.decode(bytes)
    end

    test "decodes intseq as range" do
      seq = [0x0A, 1, 10, 1]
      bytes = Msgpax.pack!(seq) |> IO.iodata_to_binary()

      assert {:ok, 1..10} = BinaryDecoder.decode(bytes)
    end

    test "decodes intseq with step" do
      seq = [0x0A, 0, 10, 2]
      bytes = Msgpax.pack!(seq) |> IO.iodata_to_binary()

      assert {:ok, 0..10//2} = BinaryDecoder.decode(bytes)
    end

    test "decodes set" do
      set = [0x06, ["a", "b", "c"]]
      bytes = Msgpax.pack!(set) |> IO.iodata_to_binary()

      assert {:ok, result} = BinaryDecoder.decode(bytes)
      assert result == MapSet.new(["a", "b", "c"])
    end

    test "decodes map type" do
      map = [0x02, %{"key" => "value"}]
      bytes = Msgpax.pack!(map) |> IO.iodata_to_binary()

      assert {:ok, %{"key" => "value"}} = BinaryDecoder.decode(bytes)
    end

    test "decodes data size" do
      ds = [0x08, 1024.0, "mb"]
      bytes = Msgpax.pack!(ds) |> IO.iodata_to_binary()

      assert {:ok, %{value: 1024.0, unit: "mb"}} = BinaryDecoder.decode(bytes)
    end

    test "decodes class metadata" do
      cls = [0x0C, "MyClass", "repl:text"]
      bytes = Msgpax.pack!(cls) |> IO.iodata_to_binary()

      assert {:ok, %{__type__: :class, name: "MyClass", module_uri: "repl:text"}} =
               BinaryDecoder.decode(bytes)
    end

    test "decodes bytes" do
      bin_data = [0x0F, Msgpax.Bin.new(<<1, 2, 3>>)]
      bytes = Msgpax.pack!(bin_data) |> IO.iodata_to_binary()

      assert {:ok, <<1, 2, 3>>} = BinaryDecoder.decode(bytes)
    end

    test "decodes object with entries" do
      object = [
        0x01,
        "Dynamic",
        "repl:text",
        [[0x11, "k1", "v1"], [0x11, "k2", "v2"]]
      ]

      bytes = Msgpax.pack!(object) |> IO.iodata_to_binary()

      assert {:ok, %{"k1" => "v1", "k2" => "v2"}} = BinaryDecoder.decode(bytes)
    end
  end

  # ── Module Source ────────────────────────────────────────────────────

  describe "ModuleSource" do
    test "text source" do
      source = ModuleSource.text(~S'name = "hello"')
      assert source.uri == "repl:text"
      assert source.text == ~S'name = "hello"'
    end

    test "file source" do
      source = ModuleSource.file("config.pkl")
      assert source.uri =~ "file://"
      assert source.uri =~ "config.pkl"
      assert source.text == nil
    end
  end

  # ── Message Encoding ────────────────────────────────────────────────

  describe "Message encoding" do
    test "encode_create_evaluator round-trips through msgpack" do
      msg = Message.encode_create_evaluator(1)
      assert {:ok, [0x20, body], <<>>} = Msgpax.unpack_slice(msg)
      assert body["requestId"] == 1
      assert is_list(body["allowedModules"])
      assert is_list(body["allowedResources"])
    end

    test "encode_evaluate round-trips through msgpack" do
      source = ModuleSource.text("x = 1")
      msg = Message.encode_evaluate(2, 100, source, expr: "x")
      assert {:ok, [0x23, body], <<>>} = Msgpax.unpack_slice(msg)
      assert body["requestId"] == 2
      assert body["evaluatorId"] == 100
      assert body["moduleUri"] == "repl:text"
      assert body["moduleText"] == "x = 1"
      assert body["expr"] == "x"
    end

    test "encode_close_evaluator round-trips through msgpack" do
      msg = Message.encode_close_evaluator(100)
      assert {:ok, [0x22, body], <<>>} = Msgpax.unpack_slice(msg)
      assert body["evaluatorId"] == 100
    end
  end

  # ── Integration (requires pkl binary) ───────────────────────────────

  describe "integration" do
    @tag :integration
    test "evaluate_text with simple module" do
      assert {:ok, result} = PklElixir.evaluate_text(~S'name = "hello"')
      assert result["name"] == "hello"
    end

    @tag :integration
    test "evaluate_text with multiple properties" do
      text = """
      name = "Alice"
      age = 30
      active = true
      """

      assert {:ok, result} = PklElixir.evaluate_text(text)
      assert result["name"] == "Alice"
      assert result["age"] == 30
      assert result["active"] == true
    end

    @tag :integration
    test "evaluate_text with expression" do
      assert {:ok, result} = PklElixir.evaluate_text(~S'name = "hello"', expr: "name")
      assert result == "hello"
    end

    @tag :integration
    test "evaluate_text with nested object" do
      text = """
      server {
        host = "localhost"
        port = 8080
      }
      """

      assert {:ok, result} = PklElixir.evaluate_text(text)
      assert result["server"]["host"] == "localhost"
      assert result["server"]["port"] == 8080
    end

    @tag :integration
    test "evaluate_text with list" do
      text = """
      items = List(1, 2, 3)
      """

      assert {:ok, result} = PklElixir.evaluate_text(text)
      assert result["items"] == [1, 2, 3]
    end

    @tag :integration
    test "evaluate_text returns error for invalid pkl" do
      assert {:error, %PklElixir.EvalError{}} = PklElixir.evaluate_text("invalid @@@ pkl")
    end

    @tag :integration
    test "evaluate a pkl file" do
      path = Path.join(System.tmp_dir!(), "pkl_elixir_test.pkl")
      File.write!(path, ~S'greeting = "hi from file"')

      try do
        assert {:ok, result} = PklElixir.evaluate(path)
        assert result["greeting"] == "hi from file"
      after
        File.rm(path)
      end
    end

    @tag :integration
    test "server lifecycle: create, evaluate, close" do
      alias PklElixir.{Server, ModuleSource}

      {:ok, server} = Server.start_link()

      try do
        {:ok, eval_id} = Server.create_evaluator(server)
        assert is_integer(eval_id)

        source = ModuleSource.text(~S'x = 42')
        assert {:ok, %{"x" => 42}} = Server.evaluate(server, eval_id, source)

        # Can evaluate again with same evaluator
        source2 = ModuleSource.text(~S'y = "reuse"')
        assert {:ok, %{"y" => "reuse"}} = Server.evaluate(server, eval_id, source2)

        Server.close_evaluator(server, eval_id)
      after
        GenServer.stop(server)
      end
    end

    @tag :integration
    test "custom module reader" do
      defmodule TestModuleReader do
        @behaviour PklElixir.ModuleReader

        @impl true
        def scheme, do: "test"
        @impl true
        def is_local, do: false
        @impl true
        def is_globbable, do: false
        @impl true
        def has_hierarchical_uris, do: false
        @impl true
        def read("test:" <> path) do
          case path do
            "greeting" -> {:ok, ~S'result = "hello from custom reader"'}
            _ -> {:error, "not found: #{path}"}
          end
        end
        @impl true
        def list_elements(_uri), do: {:ok, []}
      end

      text = """
      import "test:greeting"
      msg = import("test:greeting").result
      """

      assert {:ok, result} =
               PklElixir.evaluate_text(text, module_readers: [TestModuleReader])

      assert result["msg"] == "hello from custom reader"
    end

    @tag :integration
    test "custom resource reader" do
      defmodule TestResourceReader do
        @behaviour PklElixir.ResourceReader

        @impl true
        def scheme, do: "testres"
        @impl true
        def is_globbable, do: false
        @impl true
        def has_hierarchical_uris, do: false
        @impl true
        def read("testres:" <> path) do
          case path do
            "data" -> {:ok, "custom resource data"}
            _ -> {:error, "not found: #{path}"}
          end
        end
        @impl true
        def list_elements(_uri), do: {:ok, []}
      end

      text = """
      data = read("testres:data").text
      """

      assert {:ok, result} =
               PklElixir.evaluate_text(text, resource_readers: [TestResourceReader])

      assert result["data"] == "custom resource data"
    end

    @tag :integration
    test "custom module reader with create_evaluator options" do
      defmodule TestModuleReader2 do
        @behaviour PklElixir.ModuleReader

        @impl true
        def scheme, do: "inline"
        @impl true
        def is_local, do: false
        @impl true
        def is_globbable, do: false
        @impl true
        def has_hierarchical_uris, do: false
        @impl true
        def read("inline:" <> path) do
          case path do
            "config" -> {:ok, ~S'port = 9090'}
            _ -> {:error, "unknown: #{path}"}
          end
        end
        @impl true
        def list_elements(_uri), do: {:ok, []}
      end

      alias PklElixir.{Server, ModuleSource}

      {:ok, server} = Server.start_link()

      try do
        {:ok, eval_id} =
          Server.create_evaluator(server, module_readers: [TestModuleReader2])

        source = ModuleSource.text(~S'value = import("inline:config").port')
        assert {:ok, %{"value" => 9090}} = Server.evaluate(server, eval_id, source)

        Server.close_evaluator(server, eval_id)
      after
        GenServer.stop(server)
      end
    end

    @tag :integration
    test "evaluate_text with mapping" do
      text = """
      lookup: Mapping<String, Int> = new {
        ["alice"] = 1
        ["bob"] = 2
      }
      """

      assert {:ok, result} = PklElixir.evaluate_text(text)
      assert result["lookup"] == %{"alice" => 1, "bob" => 2}
    end

    @tag :integration
    test "evaluate_text with set" do
      text = """
      tags: Set<String> = Set("a", "b", "c")
      """

      assert {:ok, result} = PklElixir.evaluate_text(text)
      assert result["tags"] == MapSet.new(["a", "b", "c"])
    end

    @tag :integration
    test "evaluate_text with duration" do
      text = """
      timeout = 5.min
      """

      assert {:ok, result} = PklElixir.evaluate_text(text)
      assert result["timeout"] == %{value: 5.0, unit: "min"}
    end

    @tag :integration
    test "evaluate_text with data size" do
      text = """
      maxMem = 512.mb
      """

      assert {:ok, result} = PklElixir.evaluate_text(text)
      assert result["maxMem"] == %{value: 512.0, unit: "mb"}
    end

    @tag :integration
    test "evaluate_text with pair" do
      text = """
      pair = Pair("key", 42)
      """

      assert {:ok, result} = PklElixir.evaluate_text(text)
      assert result["pair"] == {"key", 42}
    end

    @tag :integration
    test "evaluate_text with int seq" do
      text = """
      seq = IntSeq(1, 10)
      """

      assert {:ok, result} = PklElixir.evaluate_text(text)
      assert result["seq"] == 1..10
    end

    @tag :integration
    test "evaluate_text with regex" do
      text = ~S"""
      pattern = Regex("\\d+")
      """

      assert {:ok, result} = PklElixir.evaluate_text(text)
      assert %Regex{} = result["pattern"]
    end

    @tag :integration
    test "evaluate_text with listing" do
      text = """
      items: Listing<String> = new {
        "first"
        "second"
        "third"
      }
      """

      assert {:ok, result} = PklElixir.evaluate_text(text)
      assert result["items"] == ["first", "second", "third"]
    end

    @tag :integration
    test "evaluate_text with map" do
      text = """
      lookup: Map<String, Int> = Map("x", 1, "y", 2)
      """

      assert {:ok, result} = PklElixir.evaluate_text(text)
      assert result["lookup"] == %{"x" => 1, "y" => 2}
    end

    @tag :integration
    test "evaluate_text with boolean and null" do
      text = """
      flag = true
      empty: String? = null
      """

      assert {:ok, result} = PklElixir.evaluate_text(text)
      assert result["flag"] == true
      assert result["empty"] == nil
    end

    @tag :integration
    test "evaluate_text with float" do
      text = """
      pi = 3.14159
      """

      assert {:ok, result} = PklElixir.evaluate_text(text)
      assert_in_delta result["pi"], 3.14159, 0.00001
    end

    @tag :integration
    test "pkl_version returns version string" do
      assert {:ok, version} = PklElixir.Server.pkl_version()
      assert version =~ "Pkl"
    end

    @tag :integration
    test "server works under supervision" do
      children = [
        {PklElixir.Server, name: :test_pkl_server}
      ]

      {:ok, sup} = Supervisor.start_link(children, strategy: :one_for_one)

      try do
        {:ok, eval_id} = PklElixir.Server.create_evaluator(:test_pkl_server)
        source = PklElixir.ModuleSource.text(~S'supervised = true')
        assert {:ok, %{"supervised" => true}} = PklElixir.Server.evaluate(:test_pkl_server, eval_id, source)
        PklElixir.Server.close_evaluator(:test_pkl_server, eval_id)
      after
        Supervisor.stop(sup)
      end
    end
  end
end
