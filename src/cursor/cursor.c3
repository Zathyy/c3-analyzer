<*
 Cursor is basically a pointer to a specific node
    with the ability to walk and get out data from it.

    represents some Node in the abstract syntax tree for a module
*>
module analyzer::cursor;

import analyzer::workspace;
import analyzer::core;

import std::collections::list;

import std::io;

faultdef
	INVALID_NODE
;

struct Cursor
{
	ModuleSection* section;
	Node* node;
}

fn bool Cursor.is_valid(self) @inline
{
	return self.section != null && self.node != null;
}

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
	assert(pool != null);

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

	sz node_start = self.node.offset.start;
	sz node_end   = self.node.offset.end;

	sz low  = 0;
	sz high = len - 1;

	while (low <= high)
	{
		sz mid    = low + (high - low) / 2;
		Node* err = errors[mid];

		if (node_start <= err.offset.start && err.offset.end <= node_end)
		{
			return true;
		}

		if (err.offset.start > node_end)
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
		return {};
	}

	Node* best_match = null;

	foreach (root_node : sf.ast.top_level_nodes)
	{
		Node* match = find_innermost_node(root_node, offset, sf);		
		if (match != null)
		{
			best_match = match;
		}
	}

	if (best_match == null)
	{
		return {};
	}

	return { .node = best_match, .section = sec };
}

<*

*>
fn Node* find_node_from_offset(Node* node, int offset)
{
	if (node == null) return null;

	if (offset < node.offset.start || offset > node.offset.end)
	{
		return null;
	}

	plog::debug("Found node: (%s) - (%s) %s:%s", node.kind, offset, node.offset.start, node.offset.end);

	return node;
}

<*
 Checks if the cursor's current node matches an access or path expression layout
*>
fn bool Cursor.is_access_node(&self)
{
	if (self.node == null) return false;
	return self.node.kind == ACCESS_EXPR || self.node.kind == IDENT_EXPR;
}

macro Node* find_innermost_from_nodes(SourceFile* sf, int offset, ...) @local 
{
	Node* result;
	$for int $i = 0; $i < $vaarg.len; $i++:
		$if $Typeof($vaarg[$i]) == NodeArray:
			foreach (node : $vaarg[$i])
			{
				result = find_innermost_node(node, offset, sf);
				if (result) return result;
			}
		$else
			result = find_innermost_node($vaarg[$i], offset, sf);
			if (result) return result;
		$endif
	$endfor
	return null;
}

fn Node* find_innermost_node(Node* node, int offset, SourceFile* sf)
{
	if (node == null) return null;

	if (offset < node.offset.start || offset > node.offset.end)
	{
		return null;
	}

	switch (node.kind)
	{
		case FN_DECL:
		{
			FnDecl* fndecl = node.as(FN_DECL);
			return find_innermost_from_nodes(sf, offset, fndecl.associated_type, fndecl.ret_type, fndecl.params, fndecl.attributes, fndecl.body) ?: node;
		}
		case COMPOUND_STMT:
		{
			CompoundStmt* comp = node.as(COMPOUND_STMT);

			foreach (stmt : comp.statements)
			{
				Node* inner = find_innermost_node(stmt, offset, sf);
				if (inner != null)
				{
					return inner;
				}
			}
			
			return node;
		}
		case VAR_DECL:
			VarDecl* vardecl = node.as(VAR_DECL);
			return find_innermost_from_nodes(sf, offset, vardecl.type, vardecl.init_expr, vardecl.bit_end, vardecl.attributes, vardecl.assoc_values, vardecl.next) ?: node;
		case IF_STMT:
		{
			IfStmt* if_stmt = node.as(IF_STMT);
			return find_innermost_from_nodes(sf, offset, if_stmt.condition, if_stmt.then_body, if_stmt.else_body) ?: node;
		}
		case RETURN_STMT:
		{
			ReturnStmt* ret = node.as(RETURN_STMT);
			if (ret.expr != null)
			{
				Node* inner = find_innermost_node(ret.expr, offset, sf);
				if (inner) return inner;
			}
			return node;
		}
		case EXPR_STMT:
		{
			Node* inner = find_innermost_node(node.as(EXPR_STMT).expr_stmt, offset, sf);
			return inner != null ? inner : node;
		}
		case BINARY_EXPR:
		{
			BinaryExpr* bin = node.as(BINARY_EXPR);
			return find_innermost_from_nodes(sf, offset, bin.left, bin.right) ?: node;
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
			return node;
		}
		default:
			break;
	}

	return node;
}

