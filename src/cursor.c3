<*
 Cursor is basically a pointer to a specific node
    with the ability to walk and get out data from it.

    represents some Node in the abstract syntax tree for a module
*>
module c3_parser::cursor;

import c3_parser::workspace;
import c3_parser::ast;
import c3_parser::common;
import string_pool;

import std::io;

faultdef
	INVALID_NODE
;

enum ChildVisitResult : int
{
	BREAK,
	// Terminate the entire walk
	CONTINUE,
	// Continue to the next sibling
	RECURSE
	// Dive into the children of the current node
}

alias CursorVisitor = fn ChildVisitResult(Cursor cursor, Cursor parent, void* user_data, args...);

struct Cursor
{
	ModuleSection* section;
	Node node;
}

// Helper to visit a node if it's valid
fn bool visit(Cursor child, Cursor parent, CursorVisitor visitor, void* data)
{
	ChildVisitResult res = visitor(child, parent, data);

	if (res == ChildVisitResult.BREAK) return false; // Stop the whole walk

	if (res == ChildVisitResult.RECURSE)
	{
		// Recursively visit the children of this child
		if (!visit_children(child, visitor, data)) return false;
	}

	return true; // Continue to next sibling
}

<*
 Visit children
  returns false if a break was requested
 @require parent.section != null
 @param parent : "The Cursor to visit children on"
 @param visitor : "visitor function that will be invoked for all children of 'parent'"
 @param data : "user data to be passed around"
*>
fn bool visit_children(Cursor parent, CursorVisitor visitor, void* data)
{
	Ast* ast = &parent.section.source_file.ast;
	Node n = parent.node;
	if (!n.is_valid()) return true;
	NodeKind kind = ast.get_node(n).kind;

	// TODO: more cases
	switch (kind)
	{
		case MODULE_DECL:
			{
				ModuleView v = { ast, n };
				if (!visit({ parent.section, v.path() }, parent, visitor, data)) return false;
				break;
			}
		case IMPORT_DECL:
			{
				ImportView v = { ast, n };
				if (!visit({ parent.section, v.path() }, parent, visitor, data)) return false;
				break;
			}
		case VAR_DECL:
			{
				VarDeclView v = { ast, n };
				if (!visit({ parent.section, v.type_node() }, parent, visitor, data)) return false;
				if (v.init_expr().is_valid())
				{
					if (!visit({ parent.section, v.init_expr() }, parent, visitor, data)) return false;
				}
				break;
			}
		case TYPEDEF_DECL:
			{
				TypedefView v = { ast, n };
				if (!visit({ parent.section, v.base_type() }, parent, visitor, data)) return false;
				break;
			}
		case FN_DECL:
			{
				FnView v = { ast, n };
				ParamsListView plv = v.params();
				if (v.return_type().is_valid())
				{
					if (!visit({ parent.section, v.return_type() }, parent, visitor, data)) return false;
				}
				for (uint i = 0; i < plv.count(); i++)
				{
					ParamView pv = plv.get_param(i);
					if (!visit({ parent.section, pv.handle }, parent, visitor, data)) return false;
				}
				if (v.body().is_valid())
				{
					if (!visit({ parent.section, v.body() }, parent, visitor, data)) return false;
				}
				break;
			}
		case PARAM_DECL:
			{
				ParamView v = { ast, n };
				if (v.type_node().is_valid())
				{
					if (!visit({ parent.section, v.type_node() }, parent, visitor, data)) return false;
				}
				if (v.init_expr().is_valid())
				{
					if (!visit({ parent.section, v.init_expr() }, parent, visitor, data)) return false;
				}
				break;
			}
		case BINARY_EXPR:
			{
				BinaryView v = { ast, n };
				if (!visit({ parent.section, v.left() }, parent, visitor, data)) return false;
				if (!visit({ parent.section, v.right() }, parent, visitor, data)) return false;
				break;
			}
		case COMPOUND_STMT:
			{
				CompoundView v = { ast, n };
				for (uint i = 0; i < v.len(); i++)
				{
					if (!visit({ parent.section, v.get(i) }, parent, visitor, data)) return false;
				}
				break;
			}
		case IF_STMT:
			{
				IfView v = { ast, n };
				if (!visit({ parent.section, v.condition() }, parent, visitor, data)) return false;
				if (!visit({ parent.section, v.then_block() }, parent, visitor, data)) return false;
				if (v.else_block().is_valid())
				{
					if (!visit({ parent.section, v.else_block() }, parent, visitor, data)) return false;
				}
				break;
			}
		case DEFER_STMT:
			{
				DeferView v = { ast, n };
				if (!visit({ parent.section, v.stmt() }, parent, visitor, data)) return false;
				break;
			}
		case EXPR_STMT:
			{
				ExprStmtView v = { ast, n };
				if (!visit({ parent.section, v.expr() }, parent, visitor, data)) return false;
				break;
			}
		default:
			break;
	}

	return true;
}

struct FindData @private
{
	Cursor best_match;
	uint target_pos;
}

fn ChildVisitResult find_at_visitor(Cursor c, Cursor p, void* data) @private
{
	FindData* fd = (FindData*)data;

	if (cursor::contains(&c, fd.target_pos))
	{
		fd.best_match = c;
		return ChildVisitResult.RECURSE;
	}

	return ChildVisitResult.CONTINUE;
}

<*
 Finds the deepest (most specific) node at the given byte position.
 @param [&inout] section : ""
 @param pos : "byte offset"
*>
fn Cursor find_at(ModuleSection* section, uint pos)
{
	FindData fd = { .target_pos = pos, .best_match = { section, { } } };

	foreach (node_handle : section.source_file.ast.top_level_nodes)
	{
		Cursor root = { section, (Node)node_handle };
		if (!visit(root, { section, { } }, (CursorVisitor)&find_at_visitor, &fd)) break;
	}

	return fd.best_match;
}

<*
 Gets the file the cursor is associated with.
*>
fn String Cursor.file_path(&self)
{
	return self.section.source_file.file_path;
}

<*
 Returns the actual source code text associated with this cursor.
*>
fn String Cursor.source_text(&self)
{
	if (!self.node.is_valid()) return "";
	if (self.section == null || self.section.source_file.source.len == 0) return "";

	Range range = cursor::range(self);
	return self.section.source_file.source[range.start..range.end];
}

<*
 find the associate comments/docs for specified cursor
*>
fn String docs(Cursor self)
{
	unreachable("TODO!");
}

<*
 Get the location in the source for this node
*>
fn Location location(Cursor* self)
{
	Size pos = self.section.source_file.ast.get_start_token(self.node);
	return self.section.source_file.line_map.resolve(pos);
}

<*
 Get the start and end byte offsets for the current node
*>
fn Range range(Cursor* self)
{
	Ast* ast = &self.section.source_file.ast;
	return { .start = (Size)ast.get_start_token(self.node), .end = (Size)ast.get_end_token(self.node), };
}

<*
 Checks if a raw byte position is "inside" this nodes source range.
*>
fn bool contains(Cursor* self, uint pos)
{
	Range r = cursor::range(self);
	return pos >= r.start && pos <= r.end;
}

<*
 Get the spelling/text for the current node
 @require self.section != null
 @require self.section.source_file.strings != null
*>
fn String? Cursor.spelling(&self)
{
	if (!self.node.is_valid()) return INVALID_NODE~;

	NodeView n = self.section.source_file.ast.get_node(self.node);

	Ast* ast = &self.section.source_file.ast;
	StringPool* strings = self.section.source_file.strings;
	View view = { ast, self.node };
	
	// TODO: clean up
	switch (n.kind)
	{
		case PATH:
			PathView v = (PathView)view;
			return v.get_full(strings);
		case MODULE_DECL:
		{
			ModuleView v = (ModuleView)view;
			Cursor path_cursor = { self.section, v.path() };
			return path_cursor.spelling();
		}
		case IMPORT_DECL:
		{
			ImportView v = (ImportView)view;
			Cursor path_cursor = { self.section, v.path() };
			return path_cursor.spelling();
		}
		case INT_LITERAL:
		case FLOAT_LITERAL:
		case STRING_LITERAL:
			LiteralView v = (LiteralView)view;
			return v.value(strings);
		case IDENT_EXPR:
			IdentView v = (IdentView)view;
			return v.name(strings);
		case FN_DECL:
			FnView v = (FnView)view;
			return v.name(strings);
		case STRUCT_DECL:
			StructView v = (StructView)view;
			return v.name(strings);
		case OP_OVERLOAD:
			{
				View v = { ast, self.node };
				return ((OverloadKind)v.get_uint(0)).description;
			}
		case BINARY_EXPR:
			BinaryView v = (BinaryView)view;
			return v.op().description;
		case VAR_DECL:
			VarDeclView v = (VarDeclView)view;
			return v.name(strings);
		case TYPE_EXPR:
			{
				TypeView v = { ast, self.node };
				String base = v.name(strings);

				uint ptrs = v.ptr_count();
				for (uint i = 0; i < ptrs; i++)
				{
					base = base.tconcat("*");
				}

				Node sz_node = v.array_size();
				if (sz_node.is_valid())
				{
					if ((uint)sz_node == 0)
					{
						base = base.tconcat("[*]");
					}
					else
					{
						base = string::tformat("[%d]%s", sz_node, base);
					}
				}

				uint gens = v.gen_count();
				if (gens > 0)
				{
					String gen_str = "<";
					for (uint i = 0; i < gens; i++)
					{
						Node arg = v.get_gen_arg(i);
						Cursor arg_cursor = { self.section, arg };
						String arg_spelling = arg_cursor.spelling() ?? "";

						gen_str = gen_str.tconcat(arg_spelling);
						if (i < gens - 1) gen_str = gen_str.tconcat(", ");
					}
					base = base.tconcat(gen_str);
					base = base.tconcat(">");
				}

				return base;
			}
		default:
			return "";
	}
}

// <*
// find the ModuleSection the specified Cursor belongs to.
// returns null if not found!
// 
// @param [&in] self
// *>
// fn ModuleSection* section(Cursor* self)
// {
// uint idx = (uint)self.node;
// 
// foreach (section : self.mod.sections)
// {
// if (idx >= section.start_node_idx && idx < section.end_node_idx)
// {
// assert(section.parent_module == self.mod);
// return section;
// }
// }
// 
// log::warn("No module section found for node: %s", self.node);
// return null;
// }

<*
 find the MODULE_DECL node the specified cursor belongs to

    returns a invalid node if not found
 @param [&in] self
 @require self.section != null
*>
fn Node Cursor.module_decl(&self)
{
	// ModuleSection* s = section(self);
	// if (s == null)
	// {
	// log::debug("invalid section for Node: ", self.node);
	// return (Node){};
	// }

	ModuleSection* s = self.section;
	for (uint i = s.start_node_idx; i < s.end_node_idx; i++)
	{
		Node n = (Node)s.start_node_idx;
		if (self.section.source_file.ast.get_kind(n) == MODULE_DECL)
		{
			return n;
		}
	}

	return (Node) { };
}
