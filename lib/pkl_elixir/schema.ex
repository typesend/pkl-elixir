defmodule PklElixir.Schema do
  @moduledoc """
  Generate Elixir structs from Pkl class definitions at compile time.

  Uses `pkl:reflect` to introspect a Pkl module and generates `defstruct`,
  typespecs, `@moduledoc`, `@enforce_keys`, and `from_map/1` for each
  concrete (non-abstract) class.

  ## Usage

      # Single-class module — struct generated directly on the calling module
      defmodule MyApp.User do
        use PklElixir.Schema, source: "schema/User.pkl"
      end

      %MyApp.User{name: ..., email: ..., active: ...}

      # Multi-class module — submodules generated for each concrete class
      defmodule MyApp.Shape do
        use PklElixir.Schema, source: "schema/Shape.pkl"
      end

      %MyApp.Shape.Circle{radius: ...}
      %MyApp.Shape.Rectangle{width: ..., height: ...}

      # Select a single class from a multi-class module
      defmodule MyApp.Order do
        use PklElixir.Schema, source: "schema/Order.pkl", class: "Order"
      end

      %MyApp.Order{id: ..., customer: ..., items: [...]}

  ## Type mapping

  | Pkl Type | Elixir Type |
  |----------|-------------|
  | `String` | `String.t()` |
  | `Int` | `integer()` |
  | `Float` | `float()` |
  | `Boolean` | `boolean()` |
  | `Listing<T>` | `list(T)` |
  | `Mapping<K,V>` / `Map<K,V>` | `%{K => V}` |
  | `Set<T>` | `MapSet.t()` |
  | `T?` (nullable) | `T \\| nil` |
  | Type aliases | `String.t()` |
  """

  defmacro __using__(opts) do
    source = Keyword.fetch!(opts, :source)
    class_filter = Keyword.get(opts, :class)

    caller_module = __CALLER__.module
    caller_file = __CALLER__.file

    # Resolve source path relative to the file containing the `use` statement
    abs_source =
      if Path.type(source) == :absolute do
        source
      else
        caller_file |> Path.dirname() |> Path.join(source) |> Path.expand()
      end

    # Reflect at compile time
    {:ok, classes} =
      case class_filter do
        nil -> PklElixir.Reflector.reflect(abs_source)
        name -> PklElixir.Reflector.reflect(abs_source, class: name)
      end

    # Filter out abstract classes
    concrete =
      classes
      |> Enum.reject(fn {_name, meta} -> meta["isAbstract"] end)
      |> Enum.sort_by(fn {name, _} -> name end)

    if concrete == [] do
      raise CompileError,
        description: "No concrete classes found in #{abs_source}",
        file: caller_file,
        line: __CALLER__.line
    end

    # Build a lookup of all class names (including abstract) for type resolution
    all_class_names = Map.keys(classes)

    case {concrete, class_filter} do
      # Single class selected via :class option — generate directly
      {[{_name, meta}], _filter} when not is_nil(class_filter) ->
        generate_struct_ast(meta, caller_module, all_class_names, classes)

      # Single concrete class in module — generate directly
      {[{_name, meta}], nil} ->
        generate_struct_ast(meta, caller_module, all_class_names, classes)

      # Multiple concrete classes — generate submodules
      {multiple, _} ->
        for {_name, meta} <- multiple do
          mod_name = Module.concat(caller_module, String.to_atom(meta["name"]))
          generate_submodule_ast(meta, mod_name, all_class_names, classes)
        end
    end
  end

  defp generate_struct_ast(meta, _caller_module, all_class_names, all_classes) do
    props = meta["properties"] || %{}
    prop_names = props |> Map.keys() |> Enum.sort()
    struct_keys = Enum.map(prop_names, &String.to_atom/1)

    enforce_keys =
      props
      |> Enum.reject(fn {_name, prop} -> nullable?(prop["type"]) end)
      |> Enum.map(fn {name, _} -> String.to_atom(name) end)
      |> Enum.sort()

    doc = meta["docComment"]
    type_ast = build_type_ast(props, all_class_names)

    from_map_body = build_from_map_body(props, all_class_names, all_classes)

    quote do
      if unquote(doc) do
        @moduledoc unquote(doc)
      end

      @enforce_keys unquote(enforce_keys)
      defstruct unquote(struct_keys)

      @type t :: %__MODULE__{unquote_splicing(type_ast)}

      @doc "Convert a string-keyed map (from `PklElixir.evaluate`) to this struct."
      @spec from_map(map()) :: t()
      def from_map(map) when is_map(map) do
        unquote(from_map_body)
      end
    end
  end

  defp generate_submodule_ast(meta, mod_name, all_class_names, all_classes) do
    props = meta["properties"] || %{}
    prop_names = props |> Map.keys() |> Enum.sort()
    struct_keys = Enum.map(prop_names, &String.to_atom/1)

    enforce_keys =
      props
      |> Enum.reject(fn {_name, prop} -> nullable?(prop["type"]) end)
      |> Enum.map(fn {name, _} -> String.to_atom(name) end)
      |> Enum.sort()

    doc = meta["docComment"]
    type_ast = build_type_ast(props, all_class_names)

    from_map_body = build_from_map_body(props, all_class_names, all_classes)

    quote do
      defmodule unquote(mod_name) do
        if unquote(doc) do
          @moduledoc unquote(doc)
        end

        @enforce_keys unquote(enforce_keys)
        defstruct unquote(struct_keys)

        @type t :: %__MODULE__{unquote_splicing(type_ast)}

        @doc "Convert a string-keyed map (from `PklElixir.evaluate`) to this struct."
        @spec from_map(map()) :: t()
        def from_map(map) when is_map(map) do
          unquote(from_map_body)
        end
      end
    end
  end

  defp build_type_ast(props, all_class_names) do
    props
    |> Enum.sort_by(fn {name, _} -> name end)
    |> Enum.map(fn {name, prop} ->
      key = String.to_atom(name)
      type = type_to_ast(prop["type"], all_class_names)
      {key, type}
    end)
  end

  defp type_to_ast(%{"kind" => "declared", "name" => name} = type, all_class_names) do
    case name do
      "String" ->
        quote(do: String.t())

      "Int" ->
        quote(do: integer())

      "Float" ->
        quote(do: float())

      "Boolean" ->
        quote(do: boolean())

      "Listing" ->
        case type["typeArguments"] do
          [arg] -> quote(do: [unquote(type_to_ast(arg, all_class_names))])
          _ -> quote(do: list())
        end

      "List" ->
        case type["typeArguments"] do
          [arg] -> quote(do: [unquote(type_to_ast(arg, all_class_names))])
          _ -> quote(do: list())
        end

      "Mapping" ->
        case type["typeArguments"] do
          [k, v] ->
            quote(do: %{unquote(type_to_ast(k, all_class_names)) => unquote(type_to_ast(v, all_class_names))})

          _ ->
            quote(do: map())
        end

      "Map" ->
        case type["typeArguments"] do
          [k, v] ->
            quote(do: %{unquote(type_to_ast(k, all_class_names)) => unquote(type_to_ast(v, all_class_names))})

          _ ->
            quote(do: map())
        end

      "Set" ->
        quote(do: MapSet.t())

      other ->
        if other in all_class_names do
          quote(do: map())
        else
          quote(do: term())
        end
    end
  end

  defp type_to_ast(%{"kind" => "nullable", "member" => member}, all_class_names) do
    inner = type_to_ast(member, all_class_names)
    quote(do: unquote(inner) | nil)
  end

  defp type_to_ast(%{"kind" => "typealias"}, _all_class_names) do
    # Type aliases resolve to their base type, which is typically String
    quote(do: String.t())
  end

  defp type_to_ast(%{"kind" => "union"}, _all_class_names) do
    quote(do: term())
  end

  defp type_to_ast(%{"kind" => "stringLiteral"}, _all_class_names) do
    quote(do: String.t())
  end

  defp type_to_ast(_type, _all_class_names) do
    quote(do: term())
  end

  defp build_from_map_body(props, all_class_names, all_classes) do
    required_keys =
      props
      |> Enum.reject(fn {_name, prop} -> nullable?(prop["type"]) end)
      |> Enum.map(fn {name, _} -> name end)
      |> Enum.sort()

    fields =
      props
      |> Enum.sort_by(fn {name, _} -> name end)
      |> Enum.map(fn {name, prop} ->
        key = String.to_atom(name)
        converter = converter_for_type(prop["type"], all_class_names, all_classes)

        {key, name, converter}
      end)

    field_assignments =
      Enum.map(fields, fn {key, str_name, converter} ->
        value_expr =
          case converter do
            :identity ->
              quote do: Map.get(map, unquote(str_name))

            {:list_of_class, class_name} ->
              from_map_fn = from_map_fn_for_class(class_name)

              quote do
                case Map.get(map, unquote(str_name)) do
                  nil -> nil
                  items when is_list(items) -> Enum.map(items, &unquote(from_map_fn).from_map/1)
                end
              end

            {:class_ref, class_name} ->
              from_map_fn = from_map_fn_for_class(class_name)

              quote do
                case Map.get(map, unquote(str_name)) do
                  nil -> nil
                  m when is_map(m) -> unquote(from_map_fn).from_map(m)
                end
              end

            {:abstract_class, subclass_names} ->
              match_clauses = build_abstract_match(subclass_names)

              quote do
                case Map.get(map, unquote(str_name)) do
                  nil ->
                    nil

                  m when is_map(m) ->
                    unquote(match_clauses).(m)
                end
              end
          end

        {key, value_expr}
      end)

    struct_fields = Enum.map(field_assignments, fn {key, expr} -> {key, expr} end)

    quote do
      missing =
        Enum.reject(unquote(required_keys), &Map.has_key?(map, &1))

      if missing != [] do
        raise ArgumentError,
              "missing required keys #{inspect(missing)} for #{inspect(__MODULE__)}"
      end

      struct!(__MODULE__, unquote(struct_fields))
    end
  end

  defp converter_for_type(%{"kind" => "declared", "name" => name} = type, all_class_names, all_classes) do
    case name do
      "Listing" ->
        case type["typeArguments"] do
          [%{"kind" => "declared", "name" => class_name}] ->
            if class_name in all_class_names, do: {:list_of_class, class_name}, else: :identity

          _ ->
            :identity
        end

      "List" ->
        case type["typeArguments"] do
          [%{"kind" => "declared", "name" => class_name}] ->
            if class_name in all_class_names, do: {:list_of_class, class_name}, else: :identity

          _ ->
            :identity
        end

      other ->
        if other in all_class_names do
          class_meta = all_classes[other]

          if class_meta && class_meta["isAbstract"] do
            subclass_names = find_concrete_subclasses(other, all_classes)
            {:abstract_class, subclass_names}
          else
            {:class_ref, other}
          end
        else
          :identity
        end
    end
  end

  defp converter_for_type(%{"kind" => "nullable", "member" => member}, all_class_names, all_classes) do
    converter_for_type(member, all_class_names, all_classes)
  end

  defp converter_for_type(_type, _all_class_names, _all_classes), do: :identity

  defp find_concrete_subclasses(parent_name, all_classes) do
    all_classes
    |> Enum.filter(fn {_name, meta} ->
      !meta["isAbstract"] && is_subclass_of?(meta, parent_name, all_classes)
    end)
    |> Enum.map(fn {name, _} -> name end)
    |> Enum.sort()
  end

  defp is_subclass_of?(meta, target_name, all_classes) do
    case meta["superclass"] do
      nil -> false
      ^target_name -> true
      parent -> is_subclass_of?(all_classes[parent] || %{}, target_name, all_classes)
    end
  end

  defp from_map_fn_for_class(class_name) do
    # This generates a reference to the sibling submodule.
    # At the call site, __MODULE__ is the parent, and we need Module.concat.
    mod_atom = String.to_atom(class_name)

    quote do
      Module.concat([__MODULE__ |> Module.split() |> Enum.slice(0..-2//1) |> Module.concat(), unquote(mod_atom)])
    end
  end

  defp build_abstract_match(subclass_names) do
    # Build a function that heuristically matches a map to a subclass
    # based on which struct's keys are present in the map
    clauses =
      Enum.map(subclass_names, fn name ->
        mod_atom = String.to_atom(name)

        quote do
          {unquote(name),
           fn m ->
             mod = Module.concat([__MODULE__ |> Module.split() |> Enum.slice(0..-2//1) |> Module.concat(), unquote(mod_atom)])
             mod.from_map(m)
           end}
        end
      end)

    quote do
      fn m ->
        candidates = unquote(clauses)
        map_keys = Map.keys(m) |> MapSet.new()

        # Find the subclass whose required fields best match the map's keys
        {_name, converter} =
          Enum.max_by(candidates, fn {_name, _fn} -> MapSet.size(map_keys) end)

        converter.(m)
      end
    end
  end

  defp nullable?(%{"kind" => "nullable"}), do: true
  defp nullable?(_), do: false
end
