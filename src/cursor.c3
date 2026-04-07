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
        default:
			break;
    }

	return true;
}

<*
	Gets the file the cursor is associated with.
*>
fn String file_path(Cursor* self)
{
    uint idx = (uint)self.node;
    foreach (section : self.mod.sections)
    {
        if (idx >= section.start_node_idx && idx < section.start_node_idx + section.node_count)
        {
            return section.file_path;
        }
    }

    return "unknown";
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

        case NodeKind.BINARY_EXPR:
            BinaryView v = { ast, self.node };
            return v.op().nameof;
		case NodeKind.GLOBAL_DECL:
			VarDeclView v = { ast, self.node };
			return v.name(self.mod.strings);
		case NodeKind.TYPE_EXPR:
		{
			TypeView v = { ast, self.node };
			return v.name(self.mod.strings);
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
        if (idx >= section.start_node_idx && idx < section.start_node_idx + section.node_count)
        {
            return section;
        }
    }

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

    for (uint i = 0; i < s.node_count; i++)
    {
        Node n = (Node)(s.start_node_idx + i); 
        if (ast::get_kind(&self.mod.ast, n) == NodeKind.MODULE_DECL)
        {
            return n;
        }
    }

    return (Node){};
}

fn String[] get_attribute_names(Cursor c, Allocator allocator)
{
	if (!c.node.is_valid()) return {};

    Node[] attr_nodes = get_attributes(c, allocator);
    if (attr_nodes.len == 0) return {};

    String[] names = alloc::new_array(allocator, String, attr_nodes.len);

    foreach (i, node_handle : attr_nodes)
    {
		// node_handle = 0 should be impossible here.
		assert(node_handle.is_valid());
        AttributeView av = { &c.mod.ast, node_handle };
        names[i] = av.kind().nameof;
    }

    return names;
}

<*
	Resolves all attributes for any given cursor.	
	Returns an empty slice if the node cannot have attributes or has none.
*>
fn Node[] get_attributes(Cursor c, Allocator allocator)
{
    NodeView v = ast::get_node(&c.mod.ast, c.node);
	Node head;

    switch (v.kind)
    {
		case MODULE_DECL:
		{
			ModuleView mv = { &c.mod.ast, c.node };
			head = mv.attribute();
			break;
		}
        case FN_DECL:
		{
			FnView fv = { &c.mod.ast, c.node };
			head = fv.attribute();
			break;
		}
        case GLOBAL_DECL:
		case CONST_DECL:
		case VAR_DECL:
            VarDeclView gv = { &c.mod.ast, c.node };
            head = gv.attribute();
        
        default: break;
    }

    if (!head.is_valid()) return {};
    Node[common::MAX_ATTRIBUTES] attr;
	uint count = 0;

    while (count < common::MAX_ATTRIBUTES)
    {
		if (!head.is_valid()) break;
        attr[count++] = head;
        AttributeView av = { &c.mod.ast, head };
		Node next = av.next_attribute();
		if (next == head) break;
		head = next;
 	}

    return mem::@tclone_slice(attr[0:count]);
}