module c3_parser;
import lexer;
import utils::ast;
import std::io;
import c3_parser::workspace;
import c3_parser::parser;
import c3_parser::cursor;

fn void print_usage()
{
	io::printn("Commands: ");
	io::printn("<file>        Test parser against std lib");
	io::printn("std <path-to-std>        Test parser against std lib");

	io::printn("Options:");
	io::printn("  -v -verbose          - Verbose output");
}

fn int main(String[] args) => @pool()
{
	if (args.len == 0)
	{
		print_usage();
		return -1;
	}

	foreach (param : args)
	{
		if (param == "-v" || param == "-verbose")
		{
			log::set_priority_all(LogPriority.VERBOSE);
		}
	}

    log::debug("Init...");

    Workspace ws;
    workspace::init(&ws);

	log::debug("args: %s", args);

    if (args.len >= 3 && args[1] == "std")
    {
        String path = args[2];
        test_std_lib(&ws, path)!!;
    }
	else if (args.len >= 3 && args[1] == "-f")
	{
		String path = args[2];
		parser::parse_file(&ws, path)!!;
	}
    else 
    {
		String test_path = "test/test_file.c3";
		String test_path2 = "test/test_file2.c3";

		parser::parse_file(&ws, test_path)!!;
		parser::parse_file(&ws, test_path2)!!;
    }

	log::info("num modules: %s", ws.modules.len());
	ast::dump_workspace(&ws);

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