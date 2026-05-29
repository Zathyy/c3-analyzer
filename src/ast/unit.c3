module parser::ast;
import lexer;

import string_pool;

import std::collections::list;

struct IntLiteral
{
	long value;
}

struct StringLiteral
{
	StringID value;
}

fn String? StringLiteral.get(&self, StringPool* pool) => pool.get(self.value);

struct Attribute
{
	StringID name;
	AttributeKind kind;
	NodeArray args;
}

fn String? Attribute.get_name(&self, StringPool* pool) => pool.get(self.name);


alias AttributeList = Attribute*[];