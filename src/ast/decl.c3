module parser::ast;
import lexer;

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

struct ModuleDecl
{
	Node* path;
	Option{Node} contract;
	NodeArray attributes;
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
- target: TYPE_EXPR for TYPE_ALIAS, PATH_EXPR for MODULE_ALIAS and IDENT_ALIAS.
- generic_params: Generic alias declaration parameters, e.g. Ty in `alias Stack<Ty> = List{Ty};`.
- attributes: Reserved for alias attributes; parsing currently skips them.
*>
struct AliasDecl
{
	StringID name;
	TokenKind name_kind;
	AliasDeclKind alias_kind;
	Node* target;
	StringID[] generic_params;
	NodeArray attributes;
}

<*
 TypedefDecl represents a C3 distinct type declaration.

 Fields:
- name: The interned typedef type name.
- base_type: The underlying TYPE_EXPR this distinct type is based on.
- interfaces: Optional interface type list after the typedef name.
- attributes: Attributes written on the typedef declaration or base type.
- is_inline: True when the declaration uses '= inline type'.
*>
struct TypedefDecl
{
	StringID name;
	Node* base_type;
	NodeArray interfaces;
	NodeArray attributes;
	bool is_inline;
}

struct FnDecl
{
	StringID name;
	Option{Node} associated_type;
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
	NodeArray params;
	NodeArray attributes;
}

<*
 VarDecl: represents (Global, Local, Field) variables
- type: type_expr if has type
- init_expr: if has initializer
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
	NodeArray attributes;
	Node* next;
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
*>
struct StructDecl
{
	Option{Node} contract;
	NodeArray interfaces;
	NodeArray fields;
	NodeArray attributes;
	Node* next;
	StringID name;
	bool is_union;
}
