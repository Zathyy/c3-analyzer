module c3_parser::ast;
import c3::lexer;

import c3_parser::common;
import c3_parser::diagnostics;

import std::io;
import std::collections::list;

// the root node will always be a ModuleDecl
// and will not be included in Ast.decls
//
// example where decls.len() == 3 
//
//    ModuleDecl
//     /  |  \
//    d   d   d
//
//
// where d = Decl
struct Ast
{
	List{ Decl* } decls;
}