# Language Binding Specification

> Source: https://pkl-lang.org/main/current/bindings-specification/index.html

## Overview

Pkl can be embedded in host applications through a child process model using the `pkl server` command. Communication occurs via message passing, with future support planned for a C library.

> Pkl's Java and Kotlin libraries bind to Pkl directly, and do not use message passing.

## Core Components of a Language Binding

A complete language binding implementation should include:

1. **Client Process**: Spawns `pkl server` and manages message passing communication
2. **Deserializer**: Converts Pkl binary encoding into host language structures
3. **Code Generator**: Transforms Pkl schemas into host language schemas (primarily Pkl-based with lightweight executable glue)

Reference implementations exist in [pkl-go](https://github.com/apple/pkl-go) and [pkl-swift](https://github.com/apple/pkl-swift) repositories.

## Typical Evaluation Flow

The specification provides a detailed sample flow for evaluating a module named `MyModule` with custom module readers:

### Step-by-Step Process

| Step | Action | Details |
|------|--------|---------|
| 1 | Client sends Create Evaluator Request | Includes custom module reader scheme (`customfs`) with hierarchical URIs |
| 2 | Server responds with evaluator ID | Returns `-135901` in the example |
| 3 | Client sends Evaluate Request | Specifies module URI to evaluate |
| 4-7 | Module resolution loop | Server requests file listings and module contents from client |
| 8 | Evaluation completes | Server returns result in Pkl binary encoding |
| 9 | Cleanup | Client sends Close Evaluator message |

## Message Types

Key message types in the protocol:

- **Create Evaluator Request/Response** (`0x20`/`0x21`)
- **Evaluate Request/Response** (`0x23`/`0x24`)
- **Close Evaluator** (`0x22`)
- **List Modules Request/Response** (`0x2c`/`0x2d`)
- **Read Module Request/Response** (`0x28`/`0x29`)

## Debugging

Enable verbose logging via the `PKL_DEBUG=1` environment variable to access extended diagnostic information from Pkl and client libraries.

## Related Specifications

- [Message Passing API](message-passing-api.md)
- [Binary Encoding](binary-encoding.md)
