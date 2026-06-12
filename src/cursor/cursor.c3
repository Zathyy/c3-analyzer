<*
 Cursor is basically a pointer to a specific node
    with the ability to walk and get out data from it.

    represents some Node in the abstract syntax tree for a module
*>
module parser::cursor;

import parser::workspace;
import parser::ast;
import parser::plog;

import std::io;

faultdef
	INVALID_NODE
;

<*
 Get the spelling/text for the current node
 @require self.node != null
 @require self.section != null
 @require self.section.source_file != null
 @require self.section.source_file.ast != null
*>
fn String? Cursor.spelling(&self, Allocator allocator) => @pool()
{
	StringPool* pool = &self.section.source_file.ast.string_pool;

	switch (self.node.kind)
	{
		case STRUCT_DECL:
			StructDecl* s = self.node.as(STRUCT_DECL);
			return pool.get(s.name)!;
		case VAR_DECL:
			VarDecl* v = self.node.as(VAR_DECL);
			return pool.get(v.name)!;
		case FN_DECL:
			FnDecl* func = self.node.as(FN_DECL);
			return pool.get(func.name)!;
		case MACRO_DECL:
			MacroDecl* mac = self.node.as(MACRO_DECL);
			return pool.get(mac.name)!;
		case TYPE_EXPR:
			TypeExpr* type_data = self.node.as(TYPE_EXPR);
			if (type_data.kind == TYPE_IDENTIFIER)
			{
				String type_name = pool.get(type_data.unresolved.name)!;
				if (type_data.unresolved.path != null)
				{
					PathExpr* prefix_path = type_data.unresolved.path.as(PATH_EXPR);
					String prefix_str     = prefix_path.full_path(pool, tmem)!;
					return prefix_str.tconcat(type_name).copy(allocator);
				}
				return type_name;
			}
			return "";
		default:
			return "";
	}
}

<*
 Checks if cursor has a specific attribute
*>
fn bool Cursor.has_attribute(&self, AttributeKind kind)
{
	NodeArray temp;
	switch (self.node.kind)
	{
		case STRUCT_DECL:
			StructDecl* s = self.node.as(STRUCT_DECL);
			temp = s.attributes;
			break;
		case INTERFACE_DECL:
			InterfaceDecl* inter = self.node.as(INTERFACE_DECL);
			temp = inter.attributes;
			break;
		case FN_DECL:
			FnDecl* func = self.node.as(FN_DECL);
			temp = func.attributes;
			break;
		default:
			return false;
	}

	foreach (attr : temp)
	{
		AttributeDecl* attr_decl = attr.as(ATTRIBUTE_DECL);
		if (attr_decl.kind == kind)
		{
			return true;
		}
	}

	return false;
}

<*
 use a binary-search to find wether any error node has
 the byte offset / byte range of this cursor
 Note: has not yet been tested
*>
fn bool Cursor.has_error(&self)
{
	NodeArray errors = self.section.source_file.ast.error_nodes.array_view();
	sz len           = errors.len;
	if (len == 0) return false;

	sz node_start = self.node.start_token;
	sz node_end   = self.node.end_token;

	sz low  = 0;
	sz high = len - 1;

	while (low <= high)
	{
		sz mid    = low + (high - low) / 2;
		Node* err = errors[mid];

		if (node_start <= err.end_token && err.start_token <= node_end)
		{
			return true;
		}

		if (err.start_token > node_end)
		{
			high = mid - 1;
		}
		else
		{
			low = mid + 1;
		}
	}

	return false;
}

<*

*>
fn Cursor find_at(ModuleSection* sec, int offset)
{
	SourceFile* sf = sec.source_file;

	if (sf.ast == null || sf.ast.top_level_nodes.len() == 0)
	{
		return { };
	}

	Node* best_match = null;

	foreach (root_node : sf.ast.top_level_nodes)
	{
		Node* match = find_node_from_offset(root_node, offset);
		if (match != null)
		{
			best_match = match;
			break;
		}
	}

	if (best_match == null)
	{
		return { };
	}

	return { .node = best_match, .section = sec };
}

<*

*>
fn Node* find_node_from_offset(Node* node, int offset)
{
	if (node == null) return null;

	if (offset < node.start_token || offset > node.end_token)
	{
		return null;
	}

	plog::debug("Found node: (%s) - (%s) %s:%s", node.kind, offset, node.start_token, node.end_token);

	return node;
}

<*
 Checks if the cursor's current node matches an access or path expression layout
*>
fn bool Cursor.is_access_node(&self)
{
    if (self.node == null) return false;
    return self.node.kind == ACCESS_EXPR || self.node.kind == PATH_EXPR;
}

fn Node* find_innermost_node(Node* node, int offset, SourceFile* sf)
{
    if (node == null) return null;

	Location cursor_loc = sf.line_map.resolve((sz)offset);

    switch (node.kind)
    {
        case FN_DECL:
        {
			return find_innermost_node(node.as(FN_DECL).body, offset, sf);
        }
        case COMPOUND_STMT:
        {
			CompoundStmt* comp = node.as(COMPOUND_STMT);
			Node* target_stmt = null;

			foreach (i, stmt : comp.statements)
			{
				if (offset >= stmt.start_token)
				{
					if (i + 1 < comp.statements.len && offset < comp.statements[i + 1].start_token)
					{
						target_stmt = stmt;
						break;
					}
					target_stmt = stmt;
				}
			}

			if (target_stmt != null)
			{
				Node* inner = find_innermost_node(target_stmt, offset, sf);
				return inner != null ? inner : target_stmt;
			}
			break;
        }
        case IF_STMT:
        {
            IfStmt* if_stmt = node.as(IF_STMT);

            Node* cond_inner = find_innermost_node(if_stmt.condition, offset, sf);
            if (cond_inner) return cond_inner;

            Node* then_inner = find_innermost_node(if_stmt.then_body, offset, sf);
            if (then_inner) return then_inner;

            if (if_stmt.else_body != null)
            {
                Node* else_inner = find_innermost_node(if_stmt.else_body, offset, sf);
                if (else_inner) return else_inner;
            }
            break;
        }
		case RETURN_STMT:
        {
			Location node_start_loc = sf.line_map.resolve((sz)node.start_token);

            if (cursor_loc.line > node_start_loc.line)
            {
                return null;
            }

            ReturnStmt* ret = node.as(RETURN_STMT);
            if (ret.expr != null)
            {
                return find_innermost_node(ret.expr, offset, sf);
            }
            break;
        }
        case EXPR_STMT:
        {
			Node* inner = find_innermost_node(node.as(EXPR_STMT).expr_stmt, offset, sf);
			if (!inner) return null;
			return inner;
        }
        case BINARY_EXPR:
        {
            BinaryExpr* bin = node.as(BINARY_EXPR);
            Node* left_inner = find_innermost_node(bin.left, offset, sf);
            if (left_inner) return left_inner;
            Node* right_inner = find_innermost_node(bin.right, offset, sf);
            if (right_inner) return right_inner;
            break;
        }
        case ACCESS_EXPR:
        {
            AccessExpr* access = node.as(ACCESS_EXPR);
            Node* left_inner = find_innermost_node(access.left, offset, sf);
            if (left_inner) return left_inner;
			
			if (access.member != null && access.member.kind != MISSING)
            {
                Node* member_inner = find_innermost_node(access.member, offset, sf);
                if (member_inner) return member_inner;
            }
            return node;
        }
		case IDENT_EXPR:
		{
			IdentExpr* ident = node.as(IDENT_EXPR);
			return node;
		}
        default:
            break;
    }

    return node;
}