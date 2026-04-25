# Changelog

All notable changes to dessert are documented here.

## 2026-04-20

- Added new `$expand(derive{YourType}(serialize, deserialize))` shorthand to implement the required methods
- Added support for C3 `0.8.0`
- Added optional `serialize_slice_item_start(usz idx)` and `serialize_slice_item_end(usz idx)` to the Serializer interface
- Added `flatten` option to serialized struct (will crash if deserialized at the moment)

## 2026-04-19

- Added the `fmt` `@DField` option to pass format specific arguments to the serializer.
- Added `XML` serializer in `dessert::format::xml`
- Fixed a bug that made muli-dimensional arrays impossible to serialize

## 2026-04-18

- Moved `dessert::csv` to `dessert::format::csv`
- Moved `dessert::json` to `dessert::format::json`
- Renamed `@Dessert`, `@DessertSer`, `@DessertDes`, `@DessertEnum`, `@DessertEnumSer`, `@DessertEnumDes`, `@DessertStruct`, `@DessertStructSer`, `@DessertStructDes` to
`@DField`, `@DFieldSer`, `@DFieldDes`, `@DEnum`, `@DEnumSer`, `@DEnumDes`, `@DStruct`, `@DStructSer`, `@DStructDes` (old names are still available, but depricated)

## 2026-04-12

### Added
- Unknown field skipping during deserialization (unknown fields are silently skipped by default)
- `@DessertStruct` / `@DessertStructSer` / `@DessertStructDes` attributes to control struct-level deserialization behavior
- `deny_unknown_fields` option on `@DessertStruct` — returns `UNKNOWN_FIELD` fault when an unrecognized field is encountered
- Deserialization into `Object*` for arbitrary / untyped JSON data
- `next_any()` optional method on the `Deserializer` interface
- `UNKNOWN_FIELD` fault in the `des` module
- `skip_serializing_<field>()` method protocol — if a struct defines a method with this naming pattern returning `bool`, dessert calls it before serializing that field and skips it when `true`
- `skip_if_empty` option on `@Dessert` / `@DessertSer` — skips a field during serialization when it is empty (null pointer, empty slice, or unset `Maybe`)
- Descriptive error messages printed to stderr when deserialization fails, showing the field name and previously deserialized fields

### Fixed
- Quotes inside strings were not escaped in JSON output

## 2026-04-07

### Added
- Enum serialization and deserialization (`@DessertEnum`, `@DessertEnumSer`, `@DessertEnumDes`) with `NAME`, `ORDINAL`, and `FIELD` modes
- `to_pretty_string()` on `JsonValue`
- Full primitive type support for deserialization: `bool`, `char`, `ichar`, `short`, `int`, `long`, `int128`, `ushort`, `uint`, `ulong`, `uint128`, `float`, `double`, `String`, `ZString`
- `c3po add ecoral360/dessert` install instructions

### Fixed
- `ulong` deserialization
- Enum serialization and deserialization edge cases
- `Deserializer` type is now propagated correctly through `impl_deserialize`
- `@is_serializable` now uses `@is_maybe_expr` instead of the compiletime `@is_maybe`

### Removed
- `float16` and `float128` support (unsupported by C3 standard library)

## 2026-03-29 — 2026-04-03

### Added
- Deserialization from JSON strings (`des::deserialize{T}`)
- Direct value serialization (values are serializable without wrapping)
- Dessert packaged as a proper `.c3l` library

### Fixed
- Deserialization of standalone numbers
- Serialization of null pointer values
- `bool` serialization

### Changed
- `deserialize` macro call syntax updated for clarity

## 2026-03-22 — 2026-03-28

### Added
- Initial JSON serializer (`dessert::json`)
- `impl_serialize` / `impl_deserialize` macros for structs
- `@Dessert`, `@DessertSer`, `@DessertDes` field attributes with `skip`, `rename`, and `validator` options
- Support for nested struct serialization
- Support for `Maybe` fields
- Support for slice / array / `List` fields
- Slice serializer fix
