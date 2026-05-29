module parser::ast;
import lexer;

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