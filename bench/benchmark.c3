module c3_parser_benchmarks;
import c3_parser::workspace;
import c3_parser::parser;
import c3_parser::cursor;
import c3_parser::ast;
import c3_parser::ast::views;
import c3_parser::common;
import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;
import std::os::process;

const STDLIB_PATH = "";

const String[*] FILES = {
	"anylist.c3",
	"atomic.c3",
	"bits.c3",
	"deque.c3",
	"elastic_array.c3",
	"enummap.c3",
	"enumset.c3",
};

fn void bench() @benchmark
{
	log::set_logger(&&(NullLogger) {});
	Workspace ws;
	ws.init();

	$foreach $file : FILES:
	parser::parse_file(&ws, @sprintf("bench/std/%s", $file))!!;
	$endforeach

}

// fn void bench_compiler() @benchmark
// {
//   log::set_logger(&&(NullLogger) {});
//   Workspace ws;
//   ws.init();
//
//   $foreach $file : FILES:
//     process::run({"c3c8", "-E", "compile", @sprintf("bench/std/%s", $file)})!!;
//   $endforeach
// }
//
