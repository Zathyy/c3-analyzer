module c3_parser;
import lexer;
import utils::ast;
import std::io;
import c3_parser::parser;

fn int main(String[] args) => @pool()
{
	log::set_priority_all(LogPriority.VERBOSE);

	log::debug("init..");

	Path path1 = path::temp("test/test_file.c3")!!;

	Parser parser;
	parser::init(&parser);
	defer parser::free(&parser);
	parser::parse(&parser, path1.path_string)!!;

	ast::dump(parser.ast, &parser.strings);

	return 0;
}