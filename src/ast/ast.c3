module c3_parser::ast;
import c3::lexer;

import c3_parser::common;
import c3_parser::diagnostics;

import std::io;
import std::collections::list;

struct Ast
{
	List{ Decl* } decls;
}