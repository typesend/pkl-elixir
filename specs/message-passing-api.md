# Message Passing API

> Source: https://pkl-lang.org/main/current/bindings-specification/message-passing-api.html

## Overview

All messages are encoded in [MessagePack](https://msgpack.org/index.html), as an array with two elements. The first element indicates the message type via an integer code, while the second contains the message body as a map.

Communication occurs between a client and server. The client is the host program (or external reader process), while the server provides controls for Pkl interaction or serves as the evaluator.

### Message Structure

```json
[
  <message_type_code>,
  { "key": "value", ... }
]
```

The first element is the message type code (integer); the second is the message body (map).

---

## Message Type Categories

### Client Message
A message passed from client to server.

### Server Message
A message passed from server to client.

### Request Message
A message sent with a `requestId` value. The `requestId` should be a unique number at the time of message send. The recipient must respond with a matching Response Message.

### Response Message
A message answering a Request Message, containing the same `requestId`.

### One Way Message
A fire-and-forget message requiring no response.

---

## Message Definitions

All schemas use Pkl notation. Nullable types should be omitted rather than set to `nil`.

---

### Create Evaluator Request

- **Code:** `0x20`
- **Type:** Client Request

Establishes an evaluator with specified settings.

**Schema:**

```pkl
requestId: Int

allowedModules: Listing<String>?
allowedResources: Listing<String>?
clientModuleReaders: Listing<ClientModuleReader>?
clientResourceReaders: Listing<ClientResourceReader>?

modulePaths: Listing<String>?
env: Mapping<String, String>?
properties: Mapping<String, String>?

timeoutSeconds: Int?
rootDir: String?
cacheDir: String?
outputFormat: String?

project: Project?
http: Http?
```

**Supporting Types:**

```pkl
class ClientResourceReader {
  scheme: String
  hasHierarchicalUris: Boolean
  isGlobbable: Boolean
}

class ClientModuleReader {
  scheme: String
  hasHierarchicalUris: Boolean
  isGlobbable: Boolean
  isLocal: Boolean
}

class Project {
  type: "local"
  packageUri: String?
  projectFileUri: String
  dependencies: Mapping<String, Project|RemoteDependency>
}

class RemoteDependency {
  type: "remote"
  packageUri: String?
  checksums: Checksums?
}

class Checksums {
  sha256: String
}

class Http {
  caCertificates: Bytes?
  proxy: Proxy?
  rewrites: Mapping<String, String>?
}

class Proxy {
  address: Uri(startsWith("http://"))?
  noProxy: Listing<String>(isDistinct)
}
```

**Example:**

```json
[
  0x20,
  {
    "requestId": 193501,
    "allowedModules": ["pkl:", "repl:"],
    "allowedResources": ["file:", "package:", "projectpackage:"]
  }
]
```

---

### Create Evaluator Response

- **Code:** `0x21`
- **Type:** Server Response

Response to Create Evaluator Request. Sets `evaluatorId` on success or `error` on failure.

**Schema:**

```pkl
requestId: Int
evaluatorId: Int?
error: String?
```

---

### Close Evaluator

- **Code:** `0x22`
- **Type:** Client One Way

Closes an evaluator and releases resources.

**Schema:**

```pkl
evaluatorId: Int
```

---

### Evaluate Request

- **Code:** `0x23`
- **Type:** Client Request

Evaluates a module.

**Schema:**

```pkl
requestId: Int
evaluatorId: Int
moduleUri: String
moduleText: String?
expr: String?
```

---

### Evaluate Response

- **Code:** `0x24`
- **Type:** Server Response

Response to Evaluate Request. On success, `result` contains the value in binary encoding.

**Schema:**

```pkl
requestId: Int
evaluatorId: Int
result: Bytes?
error: String?
```

---

### Log

- **Code:** `0x25`
- **Type:** Server One Way

Instructs client to emit a log message during Pkl execution. Logs arise from `trace()` expressions or warnings (e.g., deprecated values).

**Schema:**

```pkl
evaluatorId: Int
level: Int(this == 0 || this == 1)
message: String
frameUri: String
```

Level values: `0` = trace, `1` = warn

---

### Read Resource Request

- **Code:** `0x26`
- **Type:** Server Request

Requests resource content at a given URI when a read expression matches a client resource reader scheme.

**Schema:**

```pkl
requestId: Int
evaluatorId: Int
uri: String
```

---

### Read Resource Response

- **Code:** `0x27`
- **Type:** Client Response

Response to Read Resource Request. Sets `contents` on success or `error` on failure. Defaults to empty bytes if neither is set.

**Schema:**

```pkl
requestId: Int
evaluatorId: Int
contents: Bytes?
error: String?
```

---

### Read Module Request

- **Code:** `0x28`
- **Type:** Server Request

Requests module content at a given URI during import statement evaluation when the scheme matches a client module reader.

**Schema:**

```pkl
requestId: Int
evaluatorId: Int
uri: String
```

---

### Read Module Response

- **Code:** `0x29`
- **Type:** Client Response

Response to Read Module Request. Sets `contents` on success or `error` on failure. Defaults to empty string if neither is set.

**Schema:**

```pkl
requestId: Int
evaluatorId: Int
contents: String?
error: String?
```

---

### List Resources Request

- **Code:** `0x2a`
- **Type:** Server Request

Lists resources at a base path during globbed read evaluation when the scheme matches a client resource reader.

For non-hierarchical URIs, `dummy` serves as the path, with response containing all scheme resources.

**Schema:**

```pkl
requestId: Int
evaluatorId: Int
uri: String
```

---

### List Resources Response

- **Code:** `0x2b`
- **Type:** Client Response

Response to List Resources Request. Sets `pathElements` on success or `error` on failure. Defaults to empty list if neither is set.

**Schema:**

```pkl
requestId: Int
evaluatorId: Int
pathElements: Listing<PathElement>?
error: String?

class PathElement {
  name: String
  isDirectory: Boolean
}
```

---

### List Modules Request

- **Code:** `0x2c`
- **Type:** Server Request

Lists modules at a base path during globbed import evaluation when the scheme matches a client module reader.

For non-hierarchical URIs, `dummy` serves as the path, with response containing all scheme modules.

**Schema:**

```pkl
requestId: Int
evaluatorId: Int
uri: String
```

---

### List Modules Response

- **Code:** `0x2d`
- **Type:** Client Response

Response to List Modules Request. Sets `pathElements` on success or `error` on failure. Defaults to empty list if neither is set.

**Schema:**

```pkl
requestId: Int
evaluatorId: Int
pathElements: Listing<PathElement>?
error: String?

class PathElement {
  name: String
  isDirectory: Boolean
}
```

---

### Initialize Module Reader Request

- **Code:** `0x2e`
- **Type:** Server Request

Initializes an external module reader. Sent to external reader processes on first read of a registered scheme.

**Schema:**

```pkl
requestId: Int
scheme: String
```

---

### Initialize Module Reader Response

- **Code:** `0x2f`
- **Type:** Client Response

Returns the requested module reader specification. Sets `spec` to `null` if the external process doesn't implement the requested scheme.

**Schema:**

```pkl
requestId: Int
spec: ClientModuleReader?
```

---

### Initialize Resource Reader Request

- **Code:** `0x30`
- **Type:** Server Request

Initializes an external resource reader. Sent to external reader processes on first read of a registered scheme.

**Schema:**

```pkl
requestId: Int
scheme: String
```

---

### Initialize Resource Reader Response

- **Code:** `0x31`
- **Type:** Client Response

Returns the requested resource reader specification. Sets `spec` to `null` if the external process doesn't implement the requested scheme.

**Schema:**

```pkl
requestId: Int
spec: ClientResourceReader?
```

---

### Close External Process

- **Code:** `0x32`
- **Type:** Server One Way

Initiates graceful shutdown of the external reader process.

**Schema:** _(no properties)_

---

## Message Code Summary

| Code | Name | Direction | Type |
|------|------|-----------|------|
| `0x20` | Create Evaluator Request | Client → Server | Request |
| `0x21` | Create Evaluator Response | Server → Client | Response |
| `0x22` | Close Evaluator | Client → Server | One Way |
| `0x23` | Evaluate Request | Client → Server | Request |
| `0x24` | Evaluate Response | Server → Client | Response |
| `0x25` | Log | Server → Client | One Way |
| `0x26` | Read Resource Request | Server → Client | Request |
| `0x27` | Read Resource Response | Client → Server | Response |
| `0x28` | Read Module Request | Server → Client | Request |
| `0x29` | Read Module Response | Client → Server | Response |
| `0x2a` | List Resources Request | Server → Client | Request |
| `0x2b` | List Resources Response | Client → Server | Response |
| `0x2c` | List Modules Request | Server → Client | Request |
| `0x2d` | List Modules Response | Client → Server | Response |
| `0x2e` | Initialize Module Reader Request | Server → Client | Request |
| `0x2f` | Initialize Module Reader Response | Client → Server | Response |
| `0x30` | Initialize Resource Reader Request | Server → Client | Request |
| `0x31` | Initialize Resource Reader Response | Client → Server | Response |
| `0x32` | Close External Process | Server → Client | One Way |

## Related Specifications

- [Binary Encoding](binary-encoding.md)
- [Bindings Specification Overview](bindings-specification.md)
