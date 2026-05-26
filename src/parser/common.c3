module c3_parser::parser;

import c3_parser::ast;
import lexer;
import c3_parser::common;
import c3_parser::constants;

import std::collections::list;

struct ParseResult 
{
    List{ParserError} errors;
	String path;
	bool success;
}

fn void ParseResult.free(&self)
{
    $if $feature(C3_PARSER_LIB):
        self.errors.free();
    $endif
}