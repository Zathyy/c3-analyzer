module parser @if($feature(ANALYZER_CLI));
import utils::ast;
import std::io;
import analyzer::workspace;
import analyzer::parser;
import analyzer::core::plog;
import std::collections::maybe;
import std::collections::list;
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

	if (cli.quiet) log::set_logger(&&(NullLogger) { });

	plog::debug("Init...");

	Workspace ws;
	ws.init(mem, { .use_sema = true });
	defer ws.free();

	plog::debug("args: %s", args);

	if (try std = cli.std.get())
	{
		test_std_lib(&ws, std.path)!!;
	}
	else if (try file_path = cli.file.get())
	{
		workspace::process(&ws, tmem, { .path = file_path })!!;
	}

	plog::info("num modules: %s", ws.modules.len());

	if (cli.no_invalid)
	{
		ws.modules.@each(; name, mod)
		{
			foreach (section : mod.sections)
			{
			}
		};
	}

	if (cli.json)
	{
		ws.source_files.@each(; name, sf)
		{
			foreach (node : sf.ast.top_level_nodes) @pool()
			{
				io::printn(node.serialize(&sf.line_map, sf.ast.string_pool, indent: 2));
			};
		};
	}

	if (!cli.no_dump)
	{
	}

	return 0;
}

fn void? test_std_lib(Workspace* ws, String std_path)
{
	plog::info("Walking std lib at: %s", std_path);
	List{FileInput} paths; paths.tinit();

	Path path = path::tnew(std_path)!!;
	PathWalker walker = fn bool? (Path p, bool is_dir, void* data)
	{
		if (is_dir) return false;
		List{FileInput}* inputs = (List{FileInput}*)data;
		String sub_path = ((String)p).copy(tmem);
		inputs.push({ .path = sub_path });
		return false;
	};
	path.walk(walker, &paths)!!;
	workspace::process_batch(ws, tmem, paths.array_view())!!;
}
