# pkl_elixir

Pkl language integration for Elixir — evaluate [Pkl](https://pkl-lang.org) configuration from Elixir and get back native data structures.

- Evaluate `.pkl` files or inline Pkl text
- Full Pkl type system mapped to Elixir types (maps, lists, MapSet, Range, etc.)
- **Compile-time codegen** — `use PklElixir.Schema` generates Elixir structs from Pkl classes
- Custom module and resource readers for loading Pkl from any source
- Managed server lifecycle — reuse a single `pkl server` across evaluations
- Supervision tree support
- Expression evaluation for extracting specific values

## Quick Start

```elixir
{:ok, config} = PklElixir.evaluate("config.pkl")
config["port"]  #=> 4000

{:ok, result} = PklElixir.evaluate_text(~S'name = "hello"')
result["name"]  #=> "hello"

# Generate Elixir structs from Pkl classes at compile time
defmodule MyApp.User do
  use PklElixir.Schema, source: "schema/User.pkl"
end
```

## Installation

Requires the [Pkl CLI](https://pkl-lang.org/main/current/pkl-cli/index.html) on your PATH (or set `PKL_EXEC`).

Add `pkl_elixir` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:pkl_elixir, "~> 0.0.1"}
  ]
end
```

## Documentation

See the **[Usage Guide](guides/usage.md)** for a comprehensive walkthrough — from Pkl basics to custom readers, supervision, and real-world recipes.

API docs: `mix docs`

## License

Apache-2.0
