# Usage Guide

## What is Pkl?

[Pkl](https://pkl-lang.org) is a typed configuration language created by Apple. Unlike YAML, JSON, or TOML, Pkl catches configuration errors *before* your app runs — typos, wrong types, missing fields, and constraint violations all fail at evaluation time, not at runtime. `pkl_elixir` lets you evaluate Pkl from Elixir and get back native Elixir data structures.

## Prerequisites

**1. Install the Pkl CLI**

```bash
# macOS
brew install pkl

# Or download from https://pkl-lang.org/main/current/pkl-cli/index.html
```

Verify it works:

```bash
pkl --version
# Pkl 0.31.0 (macOS ...)
```

**2. Add the dependency**

```elixir
# mix.exs
def deps do
  [
    {:pkl_elixir, "~> 0.0.1"}
  ]
end
```

Then `mix deps.get`.

## Quick Start

**Evaluate inline Pkl text:**

```elixir
{:ok, result} = PklElixir.evaluate_text(~S'name = "hello"')
result["name"]
#=> "hello"
```

**Evaluate a `.pkl` file:**

```elixir
# config.pkl contains: port = 4000
{:ok, result} = PklElixir.evaluate("config.pkl")
result["port"]
#=> 4000
```

That's it. The result is always an Elixir map (for modules) or a native value (for expressions).

## Pkl Crash Course

If you've never written Pkl before, here's what you need to know. Each example shows the Pkl source and what `pkl_elixir` returns.

### Properties and types

Pkl properties look like variable assignments. Every value has a type.

```pkl
name = "Alice"
age = 30
pi = 3.14
active = true
```

```elixir
{:ok, result} = PklElixir.evaluate_text(text)
#=> %{"name" => "Alice", "age" => 30, "pi" => 3.14, "active" => true}
```

### Objects (nested config)

Curly braces create nested objects — like nested maps in Elixir.

```pkl
server {
  host = "localhost"
  port = 8080
}
```

```elixir
result["server"]["host"]  #=> "localhost"
result["server"]["port"]  #=> 8080
```

### Nullable types

Use `?` to make a type nullable. `null` becomes Elixir `nil`.

```pkl
nickname: String? = null
```

```elixir
result["nickname"]  #=> nil
```

### Lists and Listings

`List` is fixed-length, `Listing` is open (extendable). Both become Elixir lists.

```pkl
colors = List("red", "green", "blue")

sizes: Listing<Int> = new {
  10
  20
  30
}
```

```elixir
result["colors"]  #=> ["red", "green", "blue"]
result["sizes"]   #=> [10, 20, 30]
```

### Maps and Mappings

`Map` is a key-value collection. `Mapping` is similar but open.

```pkl
lookup: Mapping<String, Int> = new {
  ["alice"] = 1
  ["bob"] = 2
}
```

```elixir
result["lookup"]  #=> %{"alice" => 1, "bob" => 2}
```

### Sets

```pkl
tags: Set<String> = Set("web", "api", "prod")
```

```elixir
result["tags"]  #=> MapSet.new(["web", "api", "prod"])
```

### Type annotations and constraints

This is where Pkl shines. You can constrain values at the type level. If a constraint fails, evaluation returns an error — *before* your app uses bad config.

```pkl
port: UInt16          // must be 0-65535
name: String(length >= 1)  // can't be empty
env: "dev"|"staging"|"prod"  // must be one of these
```

If you try `port = -1`, Pkl returns an error. `pkl_elixir` gives you `{:error, %PklElixir.EvalError{}}`.

### Imports, amends, and extends

Pkl modules can build on each other. `amends` takes a base and overrides specific properties. `extends` inherits and adds.

```pkl
// base.pkl
host = "localhost"
port = 4000

// prod.pkl
amends "base.pkl"
host = "prod.example.com"
port = 443
```

```elixir
{:ok, result} = PklElixir.evaluate("prod.pkl")
#=> %{"host" => "prod.example.com", "port" => 443}
```

## Type Mapping Reference

Every Pkl type maps to a specific Elixir type:

| Pkl Type | Elixir Type | Example |
|----------|------------|---------|
| `String` | `String.t()` | `"hello"` |
| `Int` | `integer()` | `42` |
| `Float` | `float()` | `3.14` |
| `Boolean` | `boolean()` | `true` |
| `Null` | `nil` | `nil` |
| Object | `map()` | `%{"name" => "Alice"}` |
| `List` | `list()` | `[1, 2, 3]` |
| `Listing` | `list()` | `["a", "b"]` |
| `Map` | `map()` | `%{"x" => 1}` |
| `Mapping` | `map()` | `%{"key" => "val"}` |
| `Set` | `MapSet.t()` | `MapSet.new(["a", "b"])` |
| `Duration` | `%{value: float(), unit: String.t()}` | `%{value: 5.0, unit: "min"}` |
| `DataSize` | `%{value: float(), unit: String.t()}` | `%{value: 512.0, unit: "mb"}` |
| `Pair` | `tuple()` | `{"key", 42}` |
| `IntSeq` | `Range.t()` | `1..10` or `0..10//2` |
| `Regex` | `Regex.t()` | `~r/\d+/` |

## Evaluating Expressions

By default, evaluating a module returns all its properties as a map. Use `:expr` to extract a single value:

```elixir
# Get the whole module
{:ok, result} = PklElixir.evaluate_text(~S'name = "Alice"; age = 30')
result  #=> %{"name" => "Alice", "age" => 30}

# Get just one property
{:ok, name} = PklElixir.evaluate_text(~S'name = "Alice"; age = 30', expr: "name")
name  #=> "Alice"

# Evaluate a computed expression
{:ok, greeting} = PklElixir.evaluate_text(
  ~S'name = "Alice"',
  expr: ~S'"Hello, \(name)!"'
)
greeting  #=> "Hello, Alice!"
```

Use `:expr` when you only need one value — it's slightly more efficient than evaluating the entire module and extracting a key.

## Working with Files

### Basic file evaluation

```elixir
{:ok, config} = PklElixir.evaluate("config/app.pkl")
```

### Suggested project layout

```
my_app/
  config/
    base.pkl          # shared defaults
    dev.pkl           # amends "base.pkl"
    prod.pkl          # amends "base.pkl"
  lib/
    my_app/
      config.ex       # loads pkl at startup
```

### Module paths

If your Pkl files import from a specific directory, use `:module_paths`:

```elixir
PklElixir.evaluate("app.pkl", module_paths: ["config/", "schemas/"])
```

## Custom Module Readers

Module readers let Pkl `import` from custom sources — a database, an API, or anything else. Implement the `PklElixir.ModuleReader` behaviour:

```elixir
defmodule MyApp.EnvReader do
  @behaviour PklElixir.ModuleReader

  # The URI scheme this reader handles (e.g., "env:DATABASE_URL")
  @impl true
  def scheme, do: "env"

  # Is this a local filesystem reader? Usually false for custom readers.
  @impl true
  def is_local, do: false

  # Can Pkl glob (wildcard) this scheme? Usually false.
  @impl true
  def is_globbable, do: false

  # Are URIs hierarchical (like file paths)? Usually false.
  @impl true
  def has_hierarchical_uris, do: false

  # Read a module by URI. Return Pkl source text.
  @impl true
  def read("env:" <> var_name) do
    case System.get_env(var_name) do
      nil -> {:error, "environment variable #{var_name} not set"}
      val -> {:ok, ~s'value = "#{val}"'}
    end
  end

  # List available modules under a URI. Return [] if not supported.
  @impl true
  def list_elements(_uri), do: {:ok, []}
end
```

Use it:

```elixir
text = ~S'dbUrl = import("env:DATABASE_URL").value'

{:ok, result} = PklElixir.evaluate_text(text,
  module_readers: [MyApp.EnvReader]
)

result["dbUrl"]  #=> "postgres://..."
```

## Custom Resource Readers

Resource readers handle `read()` calls in Pkl (as opposed to `import` for modules). They return raw bytes instead of Pkl source.

```elixir
defmodule MyApp.VaultReader do
  @behaviour PklElixir.ResourceReader

  @impl true
  def scheme, do: "vault"

  @impl true
  def is_globbable, do: false

  @impl true
  def has_hierarchical_uris, do: true

  @impl true
  def read("vault:" <> path) do
    case MyApp.Vault.read_secret(path) do
      {:ok, secret} -> {:ok, secret}
      {:error, reason} -> {:error, "vault read failed: #{reason}"}
    end
  end

  @impl true
  def list_elements(_uri), do: {:ok, []}
end
```

In Pkl, access it with `read()`:

```pkl
secret = read("vault:production/db-password").text
```

```elixir
{:ok, result} = PklElixir.evaluate_text(pkl_source,
  resource_readers: [MyApp.VaultReader]
)
```

## Managed Server Lifecycle

The convenience functions (`evaluate/2`, `evaluate_text/2`) start a fresh `pkl server` process each time. If you're evaluating multiple modules, reuse a single server to avoid the subprocess startup cost:

```elixir
alias PklElixir.{Server, ModuleSource}

# Start once
{:ok, server} = Server.start_link()

# Create an evaluator (can have multiple per server)
{:ok, eval_id} = Server.create_evaluator(server)

# Evaluate as many times as you want
{:ok, r1} = Server.evaluate(server, eval_id, ModuleSource.text(~S'x = 1'))
{:ok, r2} = Server.evaluate(server, eval_id, ModuleSource.file("config.pkl"))

# Clean up
Server.close_evaluator(server, eval_id)
GenServer.stop(server)
```

This is especially useful in:
- Web request handlers that evaluate config per-request
- Scripts that process many `.pkl` files
- Tests that run many evaluations

## Supervision

Add the server to your application's supervision tree for automatic lifecycle management:

```elixir
# lib/my_app/application.ex
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {PklElixir.Server, name: MyApp.Pkl}
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

Then use the registered name anywhere in your app:

```elixir
{:ok, eval_id} = PklElixir.Server.create_evaluator(MyApp.Pkl)
{:ok, config} = PklElixir.Server.evaluate(MyApp.Pkl, eval_id,
  PklElixir.ModuleSource.file("config.pkl")
)
PklElixir.Server.close_evaluator(MyApp.Pkl, eval_id)
```

The server automatically restarts if it crashes, and gracefully closes all evaluators on shutdown.

## Error Handling

All evaluation functions return `{:ok, result}` or `{:error, exception}`. Pattern match to handle errors:

```elixir
case PklElixir.evaluate("config.pkl") do
  {:ok, config} ->
    # Use config...
    config["port"]

  {:error, %PklElixir.EvalError{message: message}} ->
    # Pkl evaluation failed (syntax error, type error, constraint violation)
    Logger.error("Invalid config: #{message}")

  {:error, %PklElixir.InternalError{message: message}} ->
    # pkl server crashed or couldn't start
    Logger.error("Pkl server error: #{message}")
end
```

A typical Pkl error looks like:

```
–– Pkl Error ––
Type constraint `length >= 1` violated.
Value: ""

3 | name: String(length >= 1) = ""
                                ^^
at config.pkl
```

**Timeouts:** Long evaluations can be controlled with `:timeout` (default: 60 seconds):

```elixir
PklElixir.evaluate("huge_config.pkl", timeout: 120_000)
```

## Real-World Recipes

### Loading app config at startup

```elixir
# lib/my_app/config.ex
defmodule MyApp.Config do
  def load! do
    env = System.get_env("MIX_ENV", "dev")
    {:ok, config} = PklElixir.evaluate("config/#{env}.pkl")
    config
  end
end

# lib/my_app/application.ex
def start(_type, _args) do
  config = MyApp.Config.load!()

  children = [
    {MyApp.Repo, config["database"]},
    {Bandit, plug: MyApp.Router, port: config["port"]}
  ]

  Supervisor.start_link(children, strategy: :one_for_one)
end
```

With a Pkl config like:

```pkl
// config/base.pkl
port: UInt16 = 4000

database {
  hostname = "localhost"
  database = "my_app_dev"
  pool_size: UInt8 = 10
}
```

```pkl
// config/prod.pkl
amends "base.pkl"
port = 443

database {
  hostname = "db.prod.internal"
  database = "my_app_prod"
  pool_size = 25
}
```

### Validating user-provided configuration

Pkl's type system makes it a great validator. Accept untrusted config and let Pkl reject anything invalid:

```elixir
defmodule MyApp.ConfigValidator do
  @schema """
  port: UInt16
  host: String(length >= 1)
  workers: UInt8(this >= 1 && this <= 64)
  log_level: "debug"|"info"|"warn"|"error"
  """

  def validate(user_config) when is_map(user_config) do
    # Build Pkl source that amends the schema with user values
    assignments =
      user_config
      |> Enum.map(fn {k, v} -> "#{k} = #{inspect_pkl(v)}" end)
      |> Enum.join("\n")

    PklElixir.evaluate_text(@schema <> "\n" <> assignments)
  end

  defp inspect_pkl(v) when is_binary(v), do: ~s'"#{v}"'
  defp inspect_pkl(v), do: to_string(v)
end

# Valid config
{:ok, _} = MyApp.ConfigValidator.validate(%{"port" => 8080, "host" => "localhost", "workers" => 4, "log_level" => "info"})

# Invalid: port out of range
{:error, %PklElixir.EvalError{}} = MyApp.ConfigValidator.validate(%{"port" => 99999, ...})
```

### Feature flags with typed constraints

```pkl
// feature_flags.pkl
class FeatureFlag {
  enabled: Boolean
  rollout_pct: Float(this >= 0 && this <= 100) = 100.0
  allowed_users: Listing<String> = new {}
}

flags: Mapping<String, FeatureFlag> = new {
  ["dark_mode"] = new { enabled = true; rollout_pct = 25.0 }
  ["new_checkout"] = new { enabled = false }
  ["beta_api"] = new { enabled = true; allowed_users { "user_123"; "user_456" } }
}
```

```elixir
{:ok, result} = PklElixir.evaluate("feature_flags.pkl", expr: "flags")

result["dark_mode"]["enabled"]       #=> true
result["dark_mode"]["rollout_pct"]   #=> 25.0
result["beta_api"]["allowed_users"]  #=> ["user_123", "user_456"]
```

## Coming Soon

Code generation from Pkl schemas to Elixir structs is planned. This will let you define your data model in Pkl and generate typed Elixir modules automatically — similar to how `pkl-gen-go` and `pkl-gen-swift` work in their respective ecosystems.
