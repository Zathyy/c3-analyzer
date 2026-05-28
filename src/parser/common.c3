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