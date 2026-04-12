<*
    Cursor is basically a pointer to a specific node
    with the ability to walk and get out data from it.

    represents some Node in the abstract syntax tree for a module
*>
module c3_parser::cursor;

import c3_parser::workspace;
import c3_parser::ast;
import c3_parser::common;

import std::io;

faultdef 
	INVALID_NODE;

enum ChildVisitResult : int
{
    BREAK,    // Terminate the entire walk
    CONTINUE, // Continue to the next sibling
    RECURSE   // Dive into the children of the current node
}

alias CursorVisitor = fn ChildVisitResult(Cursor cursor, Cursor parent, void* user_data, args...);

struct Cursor
{
    Module* mod;
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
	@require parent.mod != null
	@param parent : "The Cursor to visit children on"
	@param visitor : "visitor function that will be invoked for all children of 'parent'"
	@param data : "user data to be passed around"
*>
fn bool visit_children(Cursor parent, CursorVisitor visitor, void* data)
{
    Ast* ast = &parent.mod.ast;
    Node n = parent.node;
	if (!n.is_valid()) return true;
	NodeKind kind = ast::get_node(ast, n).kind;

    //TODO: more cases
    switch (kind)
    {
		case NodeKind.MODULE_DECL:
		{
			ModuleView v = { ast, n };
			if (!visit({ parent.mod, v.path() }, parent, visitor, data)) return false;
			break;
		}
		case NodeKind.IMPORT_DECL:
		{
			ImportView v = { ast, n };
			if (!visit({ parent.mod, v.path() }, parent, visitor, data)) return false;
			break;
		}
		case NodeKind.GLOBAL_DECL:
		{
			VarDeclView v = { ast, n };
			if (!visit({ parent.mod, v.type_node() }, parent, visitor, data)) return false;
			if (v.init_expr().is_valid())
			{
				if (!visit({ parent.mod, v.init_expr() }, parent, visitor, data)) return false;
			}
			break;
		}
		case NodeKind.TYPEDEF_DECL:
		{
			TypedefView v = { ast, n };
			if (!visit({ parent.mod, v.base_type() }, parent, visitor, data)) return false;
			break;
		}
		case NodeKind.FN_DECL:
        {
            FnView v = { ast, n };
            if (v.return_type().is_valid()) 
			{
                if (!visit({ parent.mod, v.return_type() }, parent, visitor, data)) return false;
			}
            for (uint i = 0; i < v.param_count(); i++)
			{
                if (!visit({ parent.mod, v.get_param(i) }, parent, visitor, data)) return false;
			}
            if (v.body().is_valid()) 
			{
                if (!visit({ parent.mod, v.body() }, parent, visitor, data)) return false;
			}
            break;
        }
        case NodeKind.PARAM_DECL:
        {
            ParamView v = { ast, n };
            if (v.type_node().is_valid())
            {
                if (!visit({ parent.mod, v.type_node() }, parent, visitor, data)) return false;
            }
            if (v.init_expr().is_valid())
            {
                if (!visit({ parent.mod, v.init_expr() }, parent, visitor, data)) return false;
            }
            break;
        }
        case NodeKind.BINARY_EXPR:
        {
            BinaryView v = { ast, n };
            if (!visit({ parent.mod, v.left() }, parent, visitor, data)) return false;
            if (!visit({ parent.mod, v.right() }, parent, visitor, data)) return false;
            break;
        }
        case NodeKind.COMPOUND_STMT:
        {
            CompoundView v = { ast, n };
            for (uint i = 0; i < v.len(); i++)
			{
                if (!visit({ parent.mod, v.get(i) }, parent, visitor, data)) return false;
			}
            break;
        }
        case NodeKind.IF_STMT:
        {
            IfView v = { ast, n };
            if (!visit({ parent.mod, v.condition() }, parent, visitor, data)) return false;
            if (!visit({ parent.mod, v.then_block() }, parent, visitor, data)) return false;
            if (v.else_block().is_valid())
			{
                if (!visit({ parent.mod, v.else_block() }, parent, visitor, data)) return false;
			}
            break;
        }
		case NodeKind.DEFER_STMT:
		{
			DeferView v = { ast, n };
			if (!visit({ parent.mod, v.stmt() }, parent, visitor, data)) return false;
			break;
		}
        case NodeKind.EXPR_STMT:
        {
            ExprStmtView v = { ast, n };
			if (!visit({ parent.mod, v.expr() }, parent, visitor, data)) return false;
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
	@param [&inout] mod  : ""
	@param pos : "byte offset"
*>
fn Cursor find_at(Module* mod, uint pos)
{
    FindData fd = { .target_pos = pos, .best_match = { mod, 0 } };

    foreach (node_handle : mod.ast.top_level_nodes)
    {
        Cursor root = { mod, (Node)node_handle };
        if (!visit(root, {mod, 0}, (CursorVisitor)&find_at_visitor, &fd)) break;
    }

    return fd.best_match;
}

<*
	Gets the file the cursor is associated with.
*>
fn String file_path(Cursor* self)
{
    uint idx = (uint)self.node;
    if (idx == 0) return "Invalid";

    foreach (section : self.mod.sections)
    {
        if (idx >= section.start_node_idx && idx < section.end_node_idx)
        {
            return section.file_path;
        }
    }

    return "unknown";
}

<*
    Returns the actual source code text associated with this cursor.
*>
fn String source_text(Cursor* self)
{
	if (!self.node.is_valid()) return "";
    ModuleSection* section = cursor::section(self);
    if (section == null || section.source.len == 0) return "";

    Range range = cursor::range(self);
    return section.source[range.start .. range.end];
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
	ModuleSection* section = cursor::section(self);
	if (section == null)
	{
		return (Location){
			.line = 0,
			.column = 0,
		};
	}

	Size pos = ast::get_start_token(&self.mod.ast, self.node);
	return section.line_map.resolve(pos);
}

<* 
	Get the start and end byte offsets for the current node
*>
fn Range range(Cursor* self)
{
    Ast* ast = &self.mod.ast;
    return {
        .start = (Size)ast::get_start_token(ast, self.node),
        .end = (Size)ast::get_end_token(ast, self.node),
    };
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

	@require self.mod != null
	@require self.mod.strings != null
*>
fn String? spelling(Cursor* self)
{
    if (!self.node.is_valid()) return INVALID_NODE~;

    NodeView n = ast::get_node(&self.mod.ast, self.node);

	Ast* ast = &self.mod.ast;
    switch (n.kind)
    {
		case NodeKind.PATH:
			PathView v = { ast, self.node };
			return v.get_full(self.mod.strings);
        case NodeKind.INT_LITERAL:
        case NodeKind.FLOAT_LITERAL:
        case NodeKind.STRING_LITERAL:
			LiteralView v = { ast, self.node };
			return v.value(self.mod.strings);

        case NodeKind.IDENT_EXPR:
			IdentView v = { ast, self.node };
            return v.name(self.mod.strings);

        case NodeKind.VAR_DECL_STMT:
        case NodeKind.FN_DECL:
        case NodeKind.STRUCT_DECL:
			StructView v = { ast, self.node };
			return v.name(self.mod.strings);
        case NodeKind.OP_OVERLOAD:
        {
            View v = { ast, self.node };
            return ((OverloadKind)v.get_uint(0)).nameof; 
        }
        case NodeKind.BINARY_EXPR:
            BinaryView v = { ast, self.node };
            return v.op().nameof;
		case NodeKind.GLOBAL_DECL:
			VarDeclView v = { ast, self.node };
			return v.name(self.mod.strings);
		case NodeKind.TYPE_EXPR:
		{
			TypeView v = { ast, self.node };
			String base = v.name(self.mod.strings);
		
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
					Cursor arg_cursor = { self.mod, arg };
					String arg_spelling = spelling(&arg_cursor) ?? "";
					
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

<*
    find the ModuleSection the specified Cursor belongs to.
    returns null if not found!

    @param [&in] self 
*>
fn ModuleSection* section(Cursor* self)
{
    uint idx = (uint)self.node;

    foreach (section : self.mod.sections)
    {
        if (idx >= section.start_node_idx && idx < section.end_node_idx)
        {
            assert(section.parent_module == self.mod);
            return section;
        }
    }

	log::warn("No module section found for node: %s", self.node);
    return null;
}

<*
    find the MODULE_DECL node the specified cursor belongs to

    returns a inalid node if not found

    @param [&in] self
    @require self.mod != null
*>
fn Node module_decl(Cursor* self)
{
    ModuleSection* s = section(self);
    if (s == null)
    {
        log::debug("invalid section for Node: ", self.node);
        return (Node){};
    }

    if (ast::get_kind(&self.mod.ast, s.header_node) == NodeKind.MODULE_DECL)
    {
        return s.header_node;
    }

	for (uint i = s.start_node_idx; i < s.end_node_idx; i++)
	{
        Node n = (Node)(s.start_node_idx + i); 
        if (ast::get_kind(&self.mod.ast, n) == NodeKind.MODULE_DECL)
        {
            return n;
        }
    }

    return (Node){};
}

<*
    get all attributes as a slices from the source file
*>
fn String[] get_attribute_names(Cursor c, Allocator allocator)
{
	if (!c.node.is_valid()) return {};

    Node[] attributes = cursor::get_attributes(c, tmem);
    String[] strings = alloc::new_array(tmem, String, attributes.len);

	for (Size i = 0; i < attributes.len; i++)
	{
		strings[i] = cursor::get_attribute_full_string(c, attributes[i], tmem);
	}

    return strings;
}

<*
    Returns the full string representation of an attribute node 
    (e.g., "extern(name)") using the source range.
*>
fn String get_attribute_full_string(Cursor c, Node attr_node, Allocator allocator)
{
    Cursor attr = { c.mod, attr_node };
    return cursor::source_text(&attr);
}

<*
	Resolves all attributes for any given cursor.	
	Returns an empty slice if the node cannot have attributes or has none
*>
fn Node[] get_attributes(Cursor c, Allocator allocator)
{
    if (!c.node.is_valid()) return {};

    uint offset = 0;
    NodeKind kind = ast::get_kind(&c.mod.ast, c.node);

    switch (kind)
    {
        case NodeKind.FN_DECL:
            FnView v = { &c.mod.ast, c.node };
            offset = v.attributes();
            break;
        default:
            return {};
    }

    if (offset == 0) return {};

    uint count = c.mod.ast.extra_data[offset];
    if (count == 0) return {};

    Node[] result = alloc::new_array(allocator, Node, (Size)count);
    for (uint i = 0; i < count; i++)
    {
        result[i] = (Node)c.mod.ast.extra_data[(Size)offset + 1 + i];
    }

    return result;
}