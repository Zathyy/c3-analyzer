module parser::parser;

import parser::ast;
import lexer;
import parser::common;
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
    $if $feature(parser_LIB):
        self.errors.free();
    $endif
}