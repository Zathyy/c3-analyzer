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
- Skip specific fields during serialization
- Rename fields for the output
- Validate field values before serialization
- Support for primitive types: `int`, `bool`, `String`, `char`

### Deserialization

- Handle nested structures
- Support for `Maybe` fields
- Support for slice/array/List fields
- Field renaming support (different name in the format and in C3)
- Duplicate key detection
- Floating-point support (`double`)

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

**Available attribute options:**

| Option      | Type     | Description                                                              |
|-------------|----------|--------------------------------------------------------------------------|
| `.skip`     | `bool`   | Skip this field during serialization/deserialization                    |
| `.rename`   | `String` | Use a different name for this field in the output/input                 |
| `.aliases`  | `String[]` | Alternative names to accept during deserialization (not yet implemented) |
| `.validator`| `String` | Call a validation method before serialization                           |

## Installation

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

```c3
interface Serializer {
  fn void? serialize_bool(bool b);
  fn void? serialize_char(char c);
  fn void? serialize_int(int i);
  fn void? serialize_string(String s);
  fn void? serialize_null();
  fn void? serialize_slice_start();
  fn void? serialize_slice_end(ulong len);
  fn void? serialize_field_start(String name);
  fn void? serialize_field_end();
  fn void? struct_start();
  fn void? struct_end();
  fn JsonValue? result(&self);  // Returns the serialized output
}
```

### Deserializer Interface

```c3
interface Deserializer {
  fn void? struct_start();
  fn bool? has_next_field();
  fn String? next_field_name();
  fn void? struct_end();
  fn void? slice_start();
  fn bool? has_next_slice_item();
  fn void? slice_end();
  fn String? next_string();
  fn int? next_int();
  fn double? next_double();
  fn bool? next_bool();
  fn bool? next_null();
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

| Fault                    | Description                              |
|--------------------------|------------------------------------------|
| `VALIDATOR_ERROR`        | Field validation failed during serialization |
| `DUPLICATED_KEY`         | Duplicate key found during deserialization |
| `INVALID_JSON_TYPE`      | Invalid JSON structure                   |
| `INVALID_OBJECT`         | Expected JSON object                     |
| `INVALID_FIELD`          | Invalid field format                     |
| `INVALID_ARRAY`          | Expected JSON array                      |
| `INVALID_STRING`         | Invalid string format                    |
| `INVALID_ESCAPE`         | Invalid escape sequence in string        |
| `INVALID_NUMBER`         | Invalid number format                    |
| `INVALID_BOOLEAN`       | Invalid boolean value                    |
| `INVALID_NULL`          | Invalid null value                       |

## Best Practices

1. **Always implement both interfaces**: For full round-trip support, implement both the `serialize` and the `deserialize` methods.

2. **Use skip for sensitive data**: Mark fields that shouldn't be serialized (e.g., passwords) with `.skip = true`.

## Roadmap

- [x] Serialize to JSON
- [x] Recursive struct serialization
- [x] Serialize Maybe fields
- [x] Serialize slice fields
- [x] Serialize struct fields
- [x] Skip field
- [x] Rename field
- [x] Validate field
- [x] Deserialize from JSON
- [ ] Serialize enum fields
- [ ] Serialize union fields
- [ ] Field aliases during deserialization
- [ ] Default values for missing fields

## License

MIT License
