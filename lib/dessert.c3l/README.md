# dessert 🍰

A universal serialization and deserialization library for the [C3 programming language](https://c3-lang.org/).

## Goal

Dessert provides a flexible, type-safe framework for converting C3 structs to and from various formats (e.g., JSON). It uses compile-time macros to generate serialization/deserialization code, ensuring type safety and minimal runtime overhead.

The library is built around two core interfaces:
- **Serializer**: Converts C3 structs into a target format
- **Deserializer**: Parses data from a format back into C3 structs

## Features

### Serialization

- Recursive struct serialization (nested structs)
- Support for `Maybe` fields (optional values)
- Support for slice/array/List fields
- Enum serialization (as name, ordinal, or associated field)
- Skip specific fields during serialization
- Rename fields for the output
- Validate field values before serialization
- Support for all primitive types: `bool`, `char`, `ichar`, `short`, `int`, `long`, `int128`, `ushort`, `uint`, `ulong`, `uint128`, `float`, `double`, `String`, `ZString`

### Deserialization

- Handle nested structures
- Support for `Maybe` fields
- Support for slice/array/List fields
- Enum deserialization (as name, ordinal, or associated field)
- Field renaming support (different name in the format and in C3)
- Duplicate key detection
- Support for all primitive types: `bool`, `char`, `ichar`, `short`, `int`, `long`, `int128`, `ushort`, `uint`, `ulong`, `uint128`, `float`, `double`, `String`, `ZString`

### JSON

The `dessert::json` module provides a complete JSON serializer and deserializer.

### Attributes

Use the `@Dessert` attribute to customize serialization/deserialization behavior:

```c3
struct Person {
    int age;                                  // Serialized as "age"
    String name;                              // Serialized as "name"
    bool is_cool @Dessert({ .skip = true });  // Skipped during serialization
    Maybe{Person*} friend @Dessert({ .rename = "my_friend" }); // Renamed to "my_friend"
    int score @Dessert({ .validator = "validate_score" }); // Validated before serialization
}
```

**Field attributes:**

| Attribute       | Description                                                                     |
|-----------------|---------------------------------------------------------------------------------|
| `@Dessert`      | Apply config to both serialization and deserialization                          |
| `@DessertSer`   | Apply config to serialization only                                              |
| `@DessertDes`   | Apply config to deserialization only                                            |

**Field attribute options (`Dessert` struct):**

| Option      | Type       | Description                                                              |
|-------------|------------|--------------------------------------------------------------------------|
| `.skip`     | `bool`     | Skip this field during serialization/deserialization                    |
| `.rename`   | `String`   | Use a different name for this field in the output/input                 |
| `.aliases`  | `String[]` | Alternative names to accept during deserialization (not yet implemented) |
| `.validator`| `String`   | Call a validation method before serialization                           |

**Enum attributes:**

Use `@DessertEnum` (or `@DessertEnumSer` / `@DessertEnumDes`) on an enum type to control how it is serialized:

```c3
enum Color @DessertEnum({ .as = NAME }) {
    RED,
    GREEN,
    BLUE,
}
```

| Attribute         | Description                                                    |
|-------------------|----------------------------------------------------------------|
| `@DessertEnum`    | Apply enum config to both serialization and deserialization    |
| `@DessertEnumSer` | Apply enum config to serialization only                        |
| `@DessertEnumDes` | Apply enum config to deserialization only                      |

**Enum attribute options (`DessertEnumConfig` struct):**

| Option    | Type          | Description                                                                          |
|-----------|---------------|--------------------------------------------------------------------------------------|
| `.as`     | `DessertEnum` | How to represent the enum: `NAME` (default), `ORDINAL`, or `FIELD`                  |
| `.field`  | `String`      | Name of the associated field to use when `.as = FIELD`                              |

## Installation

### Using [`c3po`](https://github.com/Ecoral360/c3po);
In your project, run 
```sh
c3po add ecoral360/dessert
```

### Manually
Get started with dessert: 
1. Make sure you have the [C3 compiler installed](https://github.com/c3lang/c3c)
2. Run `c3c init <YOUR_PROJECT>`
4. Clone the this repository into `<YOUR_PROJECT>/lib/dessert.c3l`
5. Add `"dependencies": ["dessert"]` to your `project.json`
6. You are done !

## Usage

### 1. Define Your Struct

Implement the `serialize` and `deserialize` methods using the `impl_serialize` and `impl_deserialize` macros:

```c3
struct Animal {
    String name;
    String specie;
}

fn void? Animal.serialize(&self, Serializer serializer) => 
    ser::impl_serialize(self, serializer);

fn void? Animal.deserialize(&self, Deserializer deserializer) => 
    des::impl_deserialize(self, deserializer);
```

### 2. Serialize to JSON

```c3
Animal sharpie = { .specie = "Cat", .name = "Sharpie" };
JsonSerializer s = json::serializer();
JsonValue? json = ser::serialize(&s, sharpie);
```

### 3. Deserialize from JSON String

```c3
String json_str = "{\"name\": \"Sharpie\", \"specie\": \"Cat\"}";
Animal? animal = des::deserialize{Animal}(&&json::deserializer(json_str));
```

## Complete Example

```c3
module myapp;
import std;
import dessert;
import json;

struct Animal {
  String name;
  String specie;
}

fn void? Animal.serialize(&self, Serializer serializer) => 
  ser::impl_serialize(self, serializer);

fn void? Animal.deserialize(&self, Deserializer deserializer) => 
  des::impl_deserialize(self, deserializer);

struct Person {
  int age;
  String name;
  Animal[] pets;
  Maybe{Person*} friend @Dessert({ .rename = "my_friend" });
  bool is_cool @Dessert({ .skip = true });
}

fn void? Person.serialize(&self, Serializer serializer) => 
  ser::impl_serialize(self, serializer);

fn void? Person.deserialize(&self, Deserializer deserializer) =>
  des::impl_deserialize(self, deserializer);

fn int main(String[] args) {
  Animal sharpie = { .name = "Sharpie", .specie = "Cat" };
  Person connor = { .age = 20, .name = "Connor", .is_cool = true };
  connor.pets = { sharpie };

  JsonSerializer s = json::serializer();
  ser::serialize(&s, connor)!;
  JsonValue? json = s.result();
  
  json.print()!!;
  
  Person? p = des::deserialize{Person}(&&json::deserializer(json.to_string()!));

  io::printfn("Person named %s with cat named %s", p.name, p.pets[0].name);
  
  return 0;
}
```

## Architecture

### Serializer Interface

Required methods must be implemented. Optional methods (`@optional`) fall back to a required counterpart if not provided.

```c3
interface Serializer {
  fn void? serialize_bool(bool b);

  fn void? serialize_char(char c);
  fn void? serialize_ichar(ichar c) @optional;   // falls back to serialize_long

  fn void? serialize_short(short s) @optional;   // falls back to serialize_long
  fn void? serialize_int(int i) @optional;        // falls back to serialize_long
  fn void? serialize_long(long l);
  fn void? serialize_int128(int128 i) @optional;  // returns UNSUPPORTED_DATA_TYPE if absent

  fn void? serialize_ushort(ushort s) @optional;  // falls back to serialize_ulong
  fn void? serialize_uint(uint i) @optional;      // falls back to serialize_ulong
  fn void? serialize_ulong(ulong l);
  fn void? serialize_uint128(uint128 i) @optional; // returns UNSUPPORTED_DATA_TYPE if absent

  fn void? serialize_string(String s);
  fn void? serialize_zstring(ZString s) @optional; // falls back to serialize_string

  fn void? serialize_float(float f) @optional;    // falls back to serialize_double
  fn void? serialize_double(double d);

  fn void? serialize_null();

  fn void? serialize_slice_start();
  fn void? serialize_slice_end(ulong len);

  fn void? serialize_field_start(String name);
  fn void? serialize_field_end();

  fn void? struct_start();
  fn void? struct_end();
}
```

### Deserializer Interface

Required methods must be implemented. Optional methods (`@optional`) fall back to a required counterpart if not provided.

```c3
interface Deserializer {
  fn void? struct_start();
  fn bool? has_next_field();
  fn String? next_field_name();
  fn void? struct_end();

  fn void? slice_start();
  fn bool? has_next_slice_item();
  fn void? slice_end();

  fn bool? next_bool();
  fn bool? next_null();

  fn char? next_char();
  fn ichar? next_ichar() @optional;    // falls back to next_long

  fn short? next_short() @optional;   // falls back to next_long
  fn int? next_int() @optional;        // falls back to next_long
  fn long? next_long();
  fn int128? next_int128() @optional;  // returns UNSUPPORTED_DATA_TYPE if absent

  fn ushort? next_ushort() @optional;  // falls back to next_ulong
  fn uint? next_uint() @optional;      // falls back to next_ulong
  fn ulong? next_ulong();
  fn uint128? next_uint128() @optional; // returns UNSUPPORTED_DATA_TYPE if absent

  fn String? next_string();
  fn ZString? next_zstring() @optional; // falls back to next_string

  fn float? next_float() @optional;    // falls back to next_double
  fn double? next_double();
}
```

### Adding Support for New Formats

To add support for a new format (e.g., YAML, MessagePack), implement the `Serializer` and `Deserializer` interfaces (see the [json implementation](./src/json.c3) for a model):

```c3
struct MySerializer (Serializer) {
    // Your implementation
}

fn void? MySerializer.serialize_int(&self, int i) @dynamic {
    // Format-specific implementation
}

struct MyDeserializer (Deserializer) {
    // Your implementation
}

fn int? MyDeserializer.next_int(&self) @dynamic {
    // Format-specific implementation
}
```

## Error Handling

Dessert uses C3's fault system for error handling:

| Fault                    | Module         | Description                                      |
|--------------------------|----------------|--------------------------------------------------|
| `VALIDATOR_ERROR`        | `ser`          | Field validation failed during serialization     |
| `UNSUPPORTED_DATA_TYPE`  | `ser` / `des`  | Type has no supported encoding (e.g. `int128`)   |
| `DUPLICATED_KEY`         | `des`          | Duplicate key found during deserialization       |
| `INVALID_ENUM_VALUE`     | `des`          | Enum name not found during deserialization       |
| `INVALID_JSON_TYPE`      | `json`         | Invalid JSON structure                           |
| `INVALID_OBJECT`         | `json`         | Expected JSON object                             |
| `INVALID_FIELD`          | `json`         | Invalid field format                             |
| `INVALID_ARRAY`          | `json`         | Expected JSON array                              |
| `INVALID_STRING`         | `json`         | Invalid string format                            |
| `INVALID_ESCAPE`         | `json`         | Invalid escape sequence in string                |
| `INVALID_NUMBER`         | `json`         | Invalid number format                            |
| `INVALID_BOOLEAN`        | `json`         | Invalid boolean value                            |
| `INVALID_NULL`           | `json`         | Invalid null value                               |

## Best Practices

1. **Always implement both interfaces**: For full round-trip support, implement both the `serialize` and the `deserialize` methods.

2. **Use skip for sensitive data**: Mark fields that shouldn't be serialized (e.g., passwords) with `.skip = true`.

## Roadmap

- [x] Serialize to JSON
- [x] Recursive struct serialization
- [x] Serialize Maybe fields
- [x] Serialize slice fields
- [x] Serialize struct fields
- [x] Serialize enum fields (as name, ordinal, or associated field)
- [x] Skip field
- [x] Rename field
- [x] Validate field
- [x] Deserialize from JSON
- [x] Deserialize enum fields (as name, ordinal, or associated field)
- [x] Full primitive type support (all integer, float, string variants)
- [ ] Serialize union fields
- [ ] Field aliases during deserialization
- [ ] Default values for missing fields

## License

MIT License
