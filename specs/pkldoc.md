# Pkldoc - Pkl Documentation Generator

> Source: https://pkl-lang.org/main/current/pkl-doc/index.html

## Overview

Pkldoc is a documentation website generator that produces navigable and searchable API documentation for Pkl modules. Its design draws inspiration from Scaladoc. Example documentation is available in the [Standard Library API Docs](https://pkl-lang.org/package-docs/pkl/0.31.0/).

## Features

- **Code navigation**: Hyperlinked modules, classes, functions, and properties
- **Member search**: Search by member name with advanced filtering (press `s` to activate)
  - Prefix with `m:` (modules), `c:` (classes), `f:` (functions), or `p:` (properties)
  - Camel case matching enabled by default
  - Unicode characters normalized to base forms
  - `@AlsoKnownAs` annotation for alternative member names
  - Results categorized into exact and partial matches, ranked by similarity
- **Comment folding**: Expand/collapse multi-paragraph doc comments
- **Markdown support**: Doc comments support Markdown syntax
- **Member links**: Cross-reference other members from doc comments
- **Member anchors**: Deep linking to specific members via URL anchors
- **Cross-site links**: Links between different Pkldoc websites

## CLI Usage

**Synopsis**: `pkldoc [<options>] <modules>`

### Arguments

`<modules>`: Absolute or relative URIs of docsite descriptors, package descriptors, and modules for documentation generation. Relative URIs resolve against the working directory.

### Options

| Option | Default | Description |
|--------|---------|-------------|
| `-o, --output-dir` | (none) | Directory for generated documentation |
| `--no-symlinks` | (disabled) | Create file copies instead of symbolic links |

### Common CLI Options

| Option | Default | Description |
|--------|---------|-------------|
| `--allowed-modules` | `pkl:,file:,modulepath:,https:,repl:,package:,projectpackage:` | URI patterns for loadable modules |
| `--allowed-resources` | `env:,prop:,package:,projectpackage:` | URI patterns for external resources |
| `--color` | `auto` | ANSI color: `never`, `auto`, `always` |
| `--cache-dir` | `~/.pkl/cache` | Package cache directory |
| `--no-cache` | (disabled) | Disable package caching |
| `-e, --env-var` | OS environment | Environment variables for Pkl code |
| `--module-path` | (empty) | Search paths for `modulepath:` URIs |
| `-p, --property` | (none) | External properties for Pkl code |
| `--root-dir` | (none) | Root directory for file-based modules/resources |
| `--settings` | (none) | Pkl settings file path |
| `-t, --timeout` | (none) | Evaluation timeout in seconds |
| `-w, --working-dir` | Current directory | Base path for relative module paths |
| `--ca-certificates` | (bundled) | CA certificates file (PEM format) |
| `--http-proxy` | (none) | HTTP proxy address |
| `--http-no-proxy` | (none) | Hosts bypassing proxy (supports CIDR) |
| `--http-rewrite` | (none) | Rewrite outbound HTTP(S) for mirroring |
| `--trace-mode` | `compact` | `trace()` output: `compact` or `pretty` |

## Installation

### CLI Downloads (v0.31.0)

| Platform | URL |
|----------|-----|
| macOS aarch64 | https://github.com/apple/pkl/releases/download/0.31.0/pkldoc-macos-aarch64 |
| macOS amd64 | https://github.com/apple/pkl/releases/download/0.31.0/pkldoc-macos-amd64 |
| Linux aarch64 | https://github.com/apple/pkl/releases/download/0.31.0/pkldoc-linux-aarch64 |
| Linux amd64 | https://github.com/apple/pkl/releases/download/0.31.0/pkldoc-linux-amd64 |
| Alpine Linux amd64 | https://github.com/apple/pkl/releases/download/0.31.0/pkldoc-alpine-linux-amd64 |
| Windows amd64 | https://github.com/apple/pkl/releases/download/0.31.0/pkldoc-windows-amd64.exe |

### Java Library

Available from Maven Central (requires Java 17+):

```kotlin
// Gradle Kotlin DSL
dependencies {
  implementation("org.pkl-lang:pkl-doc:0.31.0")
}
```

## Module Documentation

When generating documentation for modules directly:

- A `doc-package-info.pkl` module is required that amends `pkl.DocPackageInfo`
- Module names must start with a package name declared in `doc-package-info.pkl`
- The relative path portion must match the module's location

Example: `com.example.Bird.Parrot` should be at `$sourceCode/Bird/Parrot.pkl`.

## Package Documentation

Documentation can also be generated for published packages by passing the package URI to Pkldoc.
