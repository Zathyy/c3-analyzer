module c3_parser;
import c3::lexer;
import utils::ast;
import std::io;
import c3_parser::parser;
import c3_parser::project;

fn int main(String[] args) => @pool()
{
	log::set_priority_all(LogPriority.VERBOSE);

	log::debug("init..");

	diagnostics::init(tmem);
	defer diagnostics::free();

	Project* project = project::init(tmem);
	defer project::free(project);

	Path path1 = path::temp("test/test_file.c3")!!;
	Path path2 = path::temp("test/test_file2.c3")!!;

	if (catch err = project::parse_file(project, path1))
	{
		io::printn(err);
	}

	if (catch err = project::parse_file(project, path2))
	{
		io::printn(err);
	}

	project.modules.@each(; name, mod)
	{
		io::printfn("Module: %s", name);

		foreach (section : mod.sections)
		{
			ast::dump(section.ast);
		}
	};
	
	return 0;
}