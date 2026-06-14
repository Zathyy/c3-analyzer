module parser_benchmarks;
import analyzer::workspace;
import analyzer::parser;
import analyzer::core;
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
	log::set_logger(&&(NullLogger) { });
	Workspace ws;
	ws.init();

	$foreach $file : FILES:
		analyzer::parse_file(&ws, @sprintf("bench/std/%s", $file))!!;
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
