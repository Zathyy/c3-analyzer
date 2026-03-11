module c3_parser::project;

import c3_parser::parser;
import c3_parser::mod;
import c3_parser::ast;
import c3::lexer;

import c3_parser::common;
import c3_parser::diagnostics;

import std::collections::map;
import std::io;

faultdef 
	INVALID_MODULE;

struct Project 
{
	HashMap{ String, Module* } modules;

	Allocator alloc;
}

fn Project* init(Allocator alloc)
{
	Project* proj = allocator::new(alloc, Project);

	proj.alloc = alloc;
	proj.modules.init(alloc);

	diagnostics::init(alloc);

	return proj;
}

<*
	@require proj != null
*>
fn void free(Project* proj)
{
	allocator::free(proj.alloc, proj);
	proj.modules.free();

	diagnostics::free();
}

fn Module* get_or_create_module(Project* project, String module_name)
{
	project.modules.@each(; key, value)
	{
		if (key == module_name)
		{
			return value;
		}
	};

	Module* mod = allocator::new(project.alloc, Module);
	mod.sections.init(project.alloc);
	mod.module_name = module_name;
	project.modules.set(module_name, mod);
	return mod;
}

<*
	@param [&in] project
	@param [&inout] mod
	@param path : "path to the ModuleSections file"
*>
fn ModuleSection* new_module_section(Project* project, Module* mod, String path)
{
	ModuleSection* section = allocator::new(project.alloc, ModuleSection);
	section.ast = allocator::new(project.alloc, Ast);

	section.ast.decls.init(project.alloc);

	mod.sections.push(section);

	return section;
}

<*
	@return? file::load!, parser::parse_module!, INVALID_MODULE
*>
fn void? parse_file(Project* project, Path path)
{
	String src = (String)file::load(tmem, path.path_string)!;
	FileID file_id = diagnostics::add_file(path.path_string, src);

	Lexer lexer;
	lexer.init(src);

	Parser parser = (Parser){ 
		.lexer = lexer,
		.src = src,
	};

	parser.span.file_id = file_id;

	ModuleSection* current_section = null;

	// prime
	parser::advance(&parser)!;

	while (!parser.eof())
	{
		if (parser::token_is(&parser, TokenType.MODULE))
		{
			Decl* module_decl = parser::parse_module(&parser)!;
			Module* mod = get_or_create_module(project, module_decl.mod.path.name);

			current_section = new_module_section(project, mod, path.path_string);
			parser.section = current_section;

			continue;
		}

		if (parser.section == null)
        {
            parser.error("Code found before 'module' declaration.");
            return INVALID_MODULE~;
        }

		if (catch err = parser::parse(&parser))
		{
			if (err == parser::FOUND_MODULE) continue; 
            return err~;
		}
	}
}