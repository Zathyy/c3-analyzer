module parser::parser;

import parser::ast;
import lexer;
import parser::constants;

import std::collections::list;

struct ParseResult
{
	List{ParserError} errors;
	String path;
	bool success;
}

fn void ParseResult.free(&self)
{
	$if $feature(PARSER_LIB):
		self.errors.free();
	$endif
}

bitstruct ParseFlags : ulong
{
	bool is_interface; // Skip function bodies, disallow fields
	bool is_struct;
	bool is_global; // Top-level declarations
	bool is_local; // Inside a function/block
	bool is_var; // has a 'var'
	bool is_tlocal; // has a 'tlocal'
	bool is_inline;
	bool is_static;
	bool is_extern; // C-linkage handling
	bool is_thread_local;
	bool is_attribute; // Special parsing for @attr(...)
	bool is_type_only; // Used for casts or sizeof where names aren't expected
	bool is_const; // Context requires constant expressions
	bool is_constdef;
	bool is_call;
	bool is_expr;
	bool is_stmt;
	bool is_lamda;
	bool is_macro;
	bool is_comptime;
	bool type_as_expression;
	bool no_generics; // dont allow type parsing to check for generics
	bool skip_eos;
}

<*
 Options for path parsing.

 Fields:
 - allow_const_final: Allow a CONST_IDENT only when it is the final segment.
 - allow_attr_final: Allow an AT_IDENT only when it is the final segment.
 - as_prefix: Parse as an optional prefix before another syntax node.
*>
struct PathExprOptions
{
	bool allow_const_final;
	bool allow_attr_final;
	bool as_prefix;
}