module c3_parser;
import lexer;
import utils::ast;
import std::io;
import c3_parser::workspace;
import c3_parser::parser;
import c3_parser::cursor;

fn int main(String[] args) => @pool()
{
    log::set_priority_all(LogPriority.VERBOSE);
    log::debug("Init...");

    Workspace ws;
    workspace::init(&ws);

    String test_path = "test/test_file.c3";
    String test_path2 = "test/test_file2.c3";

    parser::parse_file(&ws, test_path)!!;
    parser::parse_file(&ws, test_path2)!!;
	log::info("num modules: %s", ws.modules.len());
	ast::dump_workspace(&ws);

    return 0;
}