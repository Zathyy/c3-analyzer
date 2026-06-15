module analyzer::core::ast;

import analyzer::core::string_pool;
import analyzer::core::lexer;

import std::collections::list;

struct ContractParam
{
	Node* name;
	StringID description;
	InOutModifier modifier;
	bool by_ref;
}

fn String? ContractParam.get_description(&self, StringPool* pool) => pool.get(self.description);

struct ContractDecl
{
	NodeArray requires;
	NodeArray ensures;
	NodeArray returns;
	NodeArray params; // ContractParam
	StringID comment;
	Node* return_desc; // ident_expr
	Node* deprecated;
	bool is_pure;
}

fn String? ContractDecl.get_comment(&self, StringPool* pool) => pool.get(self.comment);

<*
 - `generics`: generic_decl | null
*>
struct ModuleDecl
{
	Node* path;
	Option{Node} contract;
	NodeArray attributes;
	Node* generics;
}

struct ImportDecl
{
	NodeArray paths;
	NodeArray attributes;
}

<*
 AliasDecl represents the three C3 alias forms:
- TYPE_ALIAS: a TYPE_IDENT name with a type expression target.
- MODULE_ALIAS: an IDENT name whose target is a module path after '=' 'module'.
- IDENT_ALIAS: an IDENT, CONST_IDENT, or AT_IDENT name whose target path ends
  in the same token kind.

Fields:
- name: The interned alias name text.
- name_kind: The token kind used by the alias name.
- alias_kind: Which alias form was parsed.
- generics: Optional generic declaration parameters, e.g. Ty in `alias Stack<Ty> = List{Ty};`.
- target: TYPE_EXPR for TYPE_ALIAS, PATH_EXPR for MODULE_ALIAS and IDENT_ALIAS.
- attributes: Attributes written on the alias declaration before '='.
*>
struct AliasDecl
{
	StringID name;
	TokenKind name_kind;
	AliasDeclKind alias_kind;
	Node* generics;
	Node* target;
	NodeArray attributes;
}

<*
 TypedefDecl represents a C3 distinct type declaration.

 Fields:
- name: The interned typedef type name.
- base_type: The underlying TYPE_EXPR this distinct type is based on.
- generics: Optional generic declaration parameters, e.g. Type in `typedef Option<Type> = Type*`.
- interfaces: Optional interface type list after the typedef name.
- attributes: Attributes written on the typedef declaration or base type.
- is_inline: True when the declaration uses '= inline type'.
*>
struct TypedefDecl
{
	StringID name;
	Node* base_type;
	Node* generics;
	NodeArray interfaces;
	NodeArray attributes;
	bool is_inline;
}

struct FnDecl
{
	StringID name;
	Node* associated_type;
	Node* ret_type;
	Node* body;
	Option{Node} contract;
	NodeArray params;
	NodeArray attributes;
}

struct MacroDecl
{
	StringID name;
	Option{Node} associated_type;
	Option{Node} ret_type;
	Node* body;
	Option{Node} contract;
	Node* body_params;
	NodeArray params;
	NodeArray attributes;
}

<*
 VarDecl: represents (Global, Local, Field) variables
- type: type_expr if has type
- init_expr: if has initializer or if `VAR_BITFIELD` might be range start
- bit_end: for `VAR_BITFIELD` end bit range
- next: Var_decl if chained (e.g. int a, b, c; )
*>
struct VarDecl
{
	VarDeclKind kind;
	VarDeclFlags flags;
	StringID name;
	Option{Node} contract;
	Node* type;
	Node* init_expr;
	Node* bit_end;
	NodeArray attributes;
	Node* assoc_values; // enum variant associated values: VARIANT{expr, ...}
	Node* next;
}

struct EnumDecl
{
	StringID name;
	NodeArray interfaces; // optional implemented interfaces: "(" type ("," type)* ")"
	bool is_inline_backing;
	Node* backing_type; // optional: ":" type
	NodeArray assoc_params; // optional enum_param_list inside ":"
	NodeArray attributes;
	NodeArray variants;
}

struct AttributeDecl
{
	Option{Node} path;
	String name;
	NodeArray exprs;
	AttributeKind kind;
	bool is_custom;
}

struct CtExpandDecl
{
	Node* expr;
	NodeArray attributes;
}

<*
 StructDecl is both for structs & unions `is_union`
 - `generics`: generic_decl | null
*>
struct StructDecl
{
	Option{Node} contract;
	NodeArray interfaces;
	NodeArray attributes;
	NodeArray fields;
	Node* generics;
	Node* type;
	Node* next;
	StringID name;
	bool is_union;
	bool is_bitstruct;
}

struct FaultDecl
{
	Option{Node} contract;
	NodeArray attributes;
	StringID name;
}

struct FaultdefDecl
{
	Option{Node} contract;
	NodeArray faults;
}

<*
 - interfaces: parent interfaces
*>
struct InterfaceDecl
{
	Option{Node} contract;
	NodeArray interfaces;
	NodeArray attributes;
	NodeArray methods;
	StringID name;
}

struct AttrdefDecl
{
	StringID name;
	NodeArray params;
	NodeArray attributes;
}

struct CtAssertDecl
{
	Node* stmt;
}

struct GenericDecl
{
	NodeArray params;
}

struct BodyParamDecl
{
	NodeArray params;
}