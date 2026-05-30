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
	NodeArray attributes;
}

struct ImportDecl
{
	NodeArray paths;
	NodeArray attributes;
}

enum AliasDeclKind : char
{
	TYPE_ALIAS,
	MODULE_ALIAS,
	IDENT_ALIAS,
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

struct FnDecl
{
	StringID name;
	Node* associated_type;
	Node* ret_type;
	Node* body;
	NodeArray params;
	NodeArray attributes;
}

struct ParamDecl
{
	Node* type;
	Node* default_value;
	StringID name;
	TokenKind ident_kind;
	bool is_variadic;
	bool is_self;
	bool is_self_by_ref;
}

struct VarDecl
{
	VarDeclKind kind;
	VarDeclFlags flags;
	StringID name;
	Node* type;
	Node* init_expr;
	NodeArray attributes;
	Node* next; // next Var_decl if chained (e.g. int a, b, c; )
}

struct AttributeDecl
{
	Node* path;
	String name;
	NodeArray exprs;
	AttributeKind kind;
	bool is_custom;
}