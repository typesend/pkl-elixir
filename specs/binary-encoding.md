# Pkl Binary Encoding

> Source: https://pkl-lang.org/main/current/bindings-specification/binary-encoding.html

## Overview

Pkl values can be encoded into a binary format called "pkl-binary" which provides lossless serialization of underlying Pkl values. The format utilizes MessagePack encoding.

### Encoding Methods

Pkl code can be rendered into pkl-binary format through:

- The `pkl:pklbinary` standard library module
- Language binding methods such as `evaluateExpressionPklBinary` in `org.pkl.core.Evaluator` (Java)

---

## Primitives

All Pkl primitives map to their corresponding MessagePack primitive types:

| Pkl Type | MessagePack Format |
|----------|-------------------|
| `Int` | int |
| `Float` | float64 |
| `String` | str |
| `Boolean` | bool |
| `Null` | nil |

**Integer Encoding:** Pkl integers encode into the smallest int type capable of holding the value. For instance, the value `8` encodes as MessagePack `int8`.

---

## Non-Primitives

All non-primitive values are encoded as MessagePack arrays. The first slot of the array designates the value's type.

### Non-Primitive Type Codes

| Pkl Type | Code | Slot 1 | Slot 2 | Slot 3 | Slot 4 |
|----------|------|--------|--------|--------|--------|
| Typed, Dynamic | `0x01` | `str`: Class name | `str`: Enclosing module URI | `array`: Object members | — |
| Map | `0x02` | `map`: Key-value pairs | — | — | — |
| Mapping | `0x03` | `map`: Key-value pairs | — | — | — |
| List | `0x04` | `array`: Values | — | — | — |
| Listing | `0x05` | `array`: Values | — | — | — |
| Set | `0x06` | `array`: Values | — | — | — |
| Duration | `0x07` | `float64`: Duration value | `str`: Unit | — | — |
| DataSize | `0x08` | `float64`: Value | `str`: Unit | — | — |
| Pair | `0x09` | `value`: First | `value`: Second | — | — |
| IntSeq | `0x0A` | `int`: Start | `int`: End | `int`: Step | — |
| Regex | `0x0B` | `str`: Regex representation | — | — | — |
| Class | `0x0C` | `str`: Class name | `str`: Module URI | — | — |
| TypeAlias | `0x0D` | `str`: TypeAlias name | `str`: Module URI | — | — |
| Function | `0x0E` | — | — | — | — |
| Bytes | `0x0F` | `bin`: Binary contents | — | — | — |

**Array Length:** The array's length is the number of slots that are filled. Decoders must defensively handle additional future slots or provide meaningful error messages.

### Duration Units

| Unit | String |
|------|--------|
| Nanoseconds | `"ns"` |
| Microseconds | `"us"` |
| Milliseconds | `"ms"` |
| Seconds | `"s"` |
| Minutes | `"min"` |
| Hours | `"h"` |
| Days | `"d"` |

### DataSize Units

| Unit | String |
|------|--------|
| Bytes | `"b"` |
| Kilobytes | `"kb"` |
| Kibibytes | `"kib"` |
| Megabytes | `"mb"` |
| Mebibytes | `"mib"` |
| Gigabytes | `"gb"` |
| Gibibytes | `"gib"` |
| Terabytes | `"tb"` |
| Tebibytes | `"tib"` |
| Petabytes | `"pb"` |
| Pebibytes | `"pib"` |

---

## Type Name Encoding

Type names follow specific encoding rules:

**For `pkl:base` module URI:**
- `ModuleClass` represents the module class itself
- Other type names correspond to types within `pkl:base`

**For all other module URIs:**
- Type names containing `#`: String after `#` represents the type in that module; string before `#` is the module name
- Type names without `#`: Represents the module class of that module

---

## Object Members

Object members encode as MessagePack arrays where the first slot designates member type:

| Member Type | Code | Slot 1 | Slot 2 | Slot 3 |
|-------------|------|--------|--------|--------|
| Property | `0x10` | `str`: Key | `value`: Property value | — |
| Entry | `0x11` | `value`: Entry key | `value`: Entry value | — |
| Element | `0x12` | `int`: Index | `value`: Element value | — |

---

## Design Principles

- Decoders should implement defensive programming practices
- Discard unknown slot values beyond documented specifications
- Provide meaningful error messages for incompatible versions
- Handle potential future extensions gracefully

## Related Specifications

- [Message Passing API](message-passing-api.md)
- [Bindings Specification Overview](bindings-specification.md)
