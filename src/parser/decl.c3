module c3_parser::parser;
import c3_parser::ast;
import lexer;

import c3_parser::common;
import std::collections::list;

fn Node? parse_module(Parser* p)
{
	uint start = p.pos;
    expect(p, TokenKind.MODULE)!;

    Node path_node = parse_path(p)!; 

    expect(p, TokenKind.EOS)!;
    return ast::add_node(p.ast, NodeKind.MODULE_DECL, start, (uint)path_node);
}