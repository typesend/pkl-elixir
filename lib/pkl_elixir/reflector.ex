defmodule PklElixir.Reflector do
  @moduledoc """
  Introspects Pkl modules using `pkl:reflect` to extract class metadata.

  Returns structured maps describing classes, properties, types, and
  doc comments — used by `PklElixir.Schema` to generate structs at compile time.
  """

  @reflect_template ~S"""
  import "pkl:reflect"

  targetMod = reflect.Module(import("{{MODULE_URI}}"))

  function typeInfo(t: reflect.Type): Dynamic = new Dynamic {
    when (t is reflect.DeclaredType) {
      when (t.referent is reflect.Class) {
        ["kind"] = "declared"
        ["name"] = (t.referent as reflect.Class).reflectee.simpleName
        when (!t.typeArguments.isEmpty) {
          ["typeArguments"] = t.typeArguments.toList().map((a) -> typeInfo(a))
        }
      }
      when (t.referent is reflect.TypeAlias) {
        ["kind"] = "typealias"
        ["name"] = (t.referent as reflect.TypeAlias).name
      }
    }
    when (t is reflect.NullableType) {
      ["kind"] = "nullable"
      ["member"] = typeInfo(t.member)
    }
    when (t is reflect.StringLiteralType) {
      ["kind"] = "stringLiteral"
      ["value"] = t.value
    }
    when (t is reflect.NothingType) {
      ["kind"] = "nothing"
    }
    when (t is reflect.UnionType) {
      ["kind"] = "union"
      ["members"] = t.members.toList().map((m) -> typeInfo(m))
    }
    when (t is reflect.ModuleType) {
      ["kind"] = "module"
    }
    when (t is reflect.UnknownType) {
      ["kind"] = "unknown"
    }
  }

  classes = targetMod.classes.toMap().mapValues((_, clazz: reflect.Class) -> new Dynamic {
    ["name"] = clazz.reflectee.simpleName
    ["isAbstract"] = clazz.modifiers.contains("abstract")
    ["docComment"] = clazz.docComment
    ["superclass"] = if (clazz.superclass.reflectee.simpleName == "Typed") null else clazz.superclass.reflectee.simpleName
    ["properties"] = clazz.properties.toMap().mapValues((_, prop: reflect.Property) -> new Dynamic {
      ["name"] = prop.name
      ["type"] = typeInfo(prop.type)
      ["docComment"] = prop.docComment
    })
  })
  """

  @doc """
  Reflect on a Pkl module to extract class metadata.

  ## Options

    * `:class` — only return metadata for a specific class name

  Returns `{:ok, classes_map}` or `{:error, reason}`.

  The returned map is keyed by class name, with each value containing:

    * `"name"` — class name
    * `"isAbstract"` — whether the class is abstract
    * `"docComment"` — doc comment string or nil
    * `"superclass"` — superclass name or nil
    * `"properties"` — map of property name to property metadata
  """
  @spec reflect(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def reflect(source_path, opts \\ []) do
    abs_path = Path.expand(source_path)
    module_uri = "file://#{abs_path}"

    pkl_text = String.replace(@reflect_template, "{{MODULE_URI}}", module_uri)

    case PklElixir.evaluate_text(pkl_text, expr: "classes") do
      {:ok, classes} when is_map(classes) ->
        filtered =
          case opts[:class] do
            nil -> classes
            name -> Map.take(classes, [name])
          end

        {:ok, filtered}

      {:error, _} = err ->
        err
    end
  end
end
