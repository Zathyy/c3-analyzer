module c3_parser;
import lexer;
import utils::ast;
import std::io;
import c3_parser::workspace;
import c3_parser::parser;
import c3_parser::cursor;
import std::collections::maybe;
import seali;

struct Cli @Command({ .name = "c3_parser", .help_on_empty = true })
{
	Maybe{String} file @Seali(arg(long, short, help = "Parse this file"));
	Maybe{String} std @Seali(arg(long, help = "Test parser against the std lib"));
	bool verbose @Seali(arg(short, long, default_value = false, help = "Verbose output"));
	bool json @Seali(arg(short, long, default_value = false, help = "Output as json"));
}

fn int main(String[] args) => @pool()
{
	Cli cli = seali::parse(Cli, args)!!;

	if (cli.verbose) log::set_priority_all(LogPriority.VERBOSE);

	log::debug("Init...");

	Workspace ws;
	ws.init();

	log::debug("args: %s", args);

	if (try std_path = cli.std.get())
	{
		test_std_lib(&ws, std_path)!!;
	}
	else if (try file_path = cli.file.get())
	{
		parser::parse_file(&ws, file_path)!!;
	}

	log::info("num modules: %s", ws.modules.len());

	if (cli.json)
	{
		ast::dump_workspace_json(&ws, "ast-debug/")!!;
	}
	else
	{
		ast::dump_workspace(&ws);
	}

	return 0;
}

fn void? test_std_lib(Workspace* ws, String std_path)
{
	log::info("Walking std lib at: %s", std_path);

	Path path = path::temp(std_path)!!;
	PathWalker walker = fn (Path p, bool is_dir, void* data)
	{
		if (!path::is_file(p)) return false;

		log::debug("Found std file: %s", p.path_string);

		if (catch err = parser::parse_file((Workspace*)data, p.path_string))
		{
			log::error("Failed to parse %s: %s", p.path_string, err);
			return true;
		}

		return false;
	};
	path.walk(walker, ws)!!;
}
