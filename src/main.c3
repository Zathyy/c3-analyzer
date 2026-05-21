module c3_parser @if($feature(C3_PARSER_CLI));
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
	Maybe{Std} std @Seali(arg(subcommand));
	Maybe{String} file @Seali(arg(long, short, help = "Parse this file"));
	bool verbose @Seali(arg(short, long, default_value = false, help = "Verbose output"));
	bool json @Seali(arg(short, long, default_value = false, help = "Output as json"));
	bool no_invalid @Seali(arg(long, default_value = false, help = "Treat invalid node as an error"));
	bool no_dump @Seali(arg(long, default_value = false, help = "Don't dump the workspace"));
	bool quiet @Seali(arg(short, long, default_value = false, help = "Don't output anything"));
}

struct Std @Command({ .name = "std", .about = "Test parser against the std lib", .help_on_empty = true })
{
	String path @Seali(arg(help = "The std path"));
}

fn int main(String[] args) => @pool()
{
	Cli cli = seali::parse(Cli, args)!!;

	if (cli.verbose) log::set_priority_all(LogPriority.VERBOSE);

	if (cli.quiet) log::set_logger(&&(NullLogger) {});

	log::debug("Init...");

	Workspace ws;
	ws.init();
	defer ws.free();

	log::debug("args: %s", args);

	if (try std = cli.std.get())
	{
		test_std_lib(&ws, std.path)!!;
	}
	else if (try file_path = cli.file.get())
	{
		parser::parse_file(&ws, file_path)!!;
	}

	log::info("num modules: %s", ws.modules.len());

	if (cli.no_invalid)
	{
		ws.modules.@each(; name, mod)
		{
			foreach (section : mod.sections) 
			{
				foreach (i, root_node : section.source_file.ast.top_level_nodes)
				{
					bool is_last = (i == section.source_file.ast.top_level_nodes.len() - 1);
					Cursor c = { section, (Node)root_node };

					utils::ast::panic_on_invalid(c, {null, {}}, null, is_last);
				}
			}
		};
	}

	if (!cli.no_dump)
	{
		if (cli.json)
		{
			ast::dump_workspace_json(&ws, "ast-debug/")!!;
		}
		else
		{
			ast::dump_workspace(&ws);
		}
	}

	return 0;
}

fn void? test_std_lib(Workspace* ws, String std_path)
{
	log::info("Walking std lib at: %s", std_path);

	Path path = path::tnew(std_path)!!;
	PathWalker walker = fn bool? (Path p, bool is_dir, void* data)
	{
		if (is_dir) return false;
		if (catch err = parser::parse_file((Workspace*)data, p))
		{
			io::printfn("Failed to parse %s: %s", p, err);
			return true;
		}

		return false;
	};
	path.walk(walker, ws)!!;
}
