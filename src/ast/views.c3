module c3_parser::ast;

import string_pool;
import c3_parser::common;
import lexer;

struct NodeView
{
	NodeKind kind;
	uint start_token_idx;
	uint end_token_idx;
	uint extra_idx;
}

struct View
{
	Ast* ast;
	Node handle;
}

fn Node View.get_extra_index(self) => (Node)self.ast.extra_indices[(Size)self.handle];

macro View.get(self, $offset)
{
	return (Node)self.ast.extra_data[(Size)self.ast.extra_indices[(Size)self.handle] + $offset];
}

macro View.get_uint(self, $offset)
{
	return (uint)self.ast.extra_data[(Size)self.ast.extra_indices[(Size)self.handle] + $offset];
}

macro View.get_at(self, $base_offset, index)
{
	Size pos = (Size)self.ast.extra_indices[(Size)self.handle] + $base_offset + index;
	return (Node)self.ast.extra_data[pos];
}

// --- General Views ---

typedef ParamView = inline View;
fn String ParamView.name(ParamView self, StringPool* pool) => pool.get((StringHandle)self.get_uint(0));
fn Node ParamView.type_node(ParamView self) => self.get(1);
fn Node ParamView.init_expr(ParamView self) => self.get(2);
fn bool ParamView.is_ref(ParamView self) => self.get_uint(3) != 0;

typedef AttributeView = inline View;

fn AttributeKind AttributeView.kind(AttributeView self) => (AttributeKind)self.get_uint(0);
fn uint AttributeView.args_offset(AttributeView self) => self.get_uint(1);
fn uint AttributeView.arg_count(AttributeView self) => self.get_uint(2);

fn Node AttributeView.get_arg(AttributeView self, uint index)
{
	assert (index < self.arg_count() , "Attribute argument index out of bounds");
	uint base = self.args_offset();
	return (Node)self.ast.extra_data[(Size)base + index];
}

typedef PathView = inline View;
fn uint PathView.len(PathView self) => self.get_uint(0);
fn StringHandle PathView.get_string_handle(PathView self, uint index) => (StringHandle)self.get_at(1, index);
fn String PathView.get_full(self, StringPool* pool)
{
	uint len = self.len();

	String result = "";
	for (uint i = 0; i < len; i++)
	{
		StringHandle sh = self.get_string_handle((StringHandle)i);
		result = result.concat(tmem, pool.get(sh));

		if (i < len - 1)
		{
			result = result.concat(tmem, "::");
		}
	}
	return result;
}
fn String PathView.get_text(PathView self, uint index, StringPool* pool)
{
	return pool.get((StringHandle)self.get_string_handle(index));
}

typedef TypeView = inline View;

fn String TypeView.name(TypeView self, StringPool* pool)
{
	uint sh = self.get_uint(0);
	return pool.get((StringHandle)sh);
}

fn uint TypeView.ptr_count(TypeView self) => self.get_uint(1);

// 0 in this case does not equal invalid it means infered size '[*]'
fn Node TypeView.array_size(TypeView self) => self.get(2);
fn uint TypeView.gen_count(TypeView self) => self.get_uint(3);
fn TypeFlags TypeView.get_flags(TypeView self) => (TypeFlags)self.get(4);
fn bool TypeView.is_vector(TypeView self) => self.get_flags().is_vector;
fn Node TypeView.get_gen_arg(TypeView self, uint index)
{
	return self.get_at(5, index);
}

// --- DECLERATIONS ---


typedef ModuleView = inline View;
fn Node ModuleView.path(self) => self.get(0);
fn Node ModuleView.generic(self) => self.get(1);
fn Node ModuleView.attribute(self) => self.get(2);

typedef ImportView = inline View;
fn Node ImportView.path(self) => self.get(0);
fn Node ImportView.attribute(self) => self.get(1);

typedef FnView = inline View;

fn String FnView.name(FnView self, StringPool* pool) => pool.get((StringHandle)self.get_uint(0));
fn Node FnView.associated(FnView self) => self.get(1);
fn Node FnView.return_type(FnView self) => self.get(2);
fn uint FnView.attributes(self) => self.get_uint(3);
fn Node FnView.body(FnView self) => self.get(5);
fn uint FnView.param_count(FnView self)
{
	uint offset = self.get_uint(4);
	return self.ast.extra_data[(Size)offset];
}
fn Node FnView.get_param(FnView self, uint index)
{
	uint offset = self.get_uint(4);
	// the param block is (count, params...) so thats why + 1
	return (Node)self.ast.extra_data[(Size)offset + 1 + index];
}

// / ---

typedef AliasView = inline View;
fn String AliasView.name(AliasView self, StringPool* pool) => pool.get((StringHandle)self.get_uint(0));
fn Node AliasView.target_type(AliasView self) => self.get(1);

typedef TypedefView = inline View;
fn String TypedefView.name(TypedefView self, StringPool* pool) => pool.get((StringHandle)self.get_uint(0));
fn Node TypedefView.base_type(TypedefView self) => self.get(1);

typedef VarDeclView = inline View;
fn String VarDeclView.name(self, StringPool* pool) => pool.get((StringHandle)self.get_uint(0));
fn Node VarDeclView.type_node(self) => self.get(1);
fn Node VarDeclView.init_expr(self) => self.get(2);
fn Node VarDeclView.attribute(self) => self.get(3);

typedef StructView = inline View;

fn String StructView.name(self, StringPool* pool) => pool.get((StringHandle)self.get_uint(0));
fn uint StructView.field_count(self) => self.get_uint(3);
fn Node StructView.field(self, uint index)
{
	return self.get_at(2, index);
}

typedef FieldView = inline View;
fn String FieldView.name(self, StringPool* pool) => pool.get((StringHandle)self.get_uint(0));
fn Node FieldView.type_node(self) => self.get(1);

// / --- STMT ---

typedef ReturnView = inline View;
fn Node ReturnView.expr(self) => self.get_extra_index();


// Extra Block Layout: [Kind, StmtNode, VarName]
typedef DeferView = inline View;
fn DeferKind DeferView.kind(self) => (DeferKind)self.get_uint(0);
fn Node DeferView.stmt(self) => self.get(1);
fn String DeferView.name(self, StringPool* pool) => pool.get((StringHandle)self.get_uint(2));

typedef ExprStmtView = inline View;
fn Node ExprStmtView.expr(self) => self.get_extra_index();

typedef ForView = inline View;

fn Node ForView.init(ForView self) => self.get(0);
fn Node ForView.cond(ForView self) => self.get(1);
fn Node ForView.inc(ForView self) => self.get(2);
fn Node ForView.body(ForView self) => self.get(3);

typedef CompoundView = inline View;

fn uint CompoundView.len(CompoundView self) => self.get_uint(0);
fn Node CompoundView.get(CompoundView self, uint index) => self.get_at(1, index);

// / ------------

// / --- EXPR ---

typedef BinaryView = inline View;
fn Node BinaryView.left(BinaryView self) => self.get(0);
fn Node BinaryView.right(BinaryView self) => self.get(1);
fn TokenKind BinaryView.op(BinaryView self) => (TokenKind)self.get_uint(2);

typedef TernaryView = inline View;
fn Node TernaryView.condition(self) => self.get(0);
fn Node TernaryView.then_expr(self) => self.get(1);
fn Node TernaryView.else_expr(self) => self.get(2);

typedef UnaryView = inline View;
fn TokenKind UnaryView.op(self) => (TokenKind)self.get_uint(0);
fn Node UnaryView.rhs(self) => self.get(1);

typedef CallView = inline View;
fn Node CallView.callee(CallView self) => self.get(0);
fn uint CallView.arg_count(CallView self) => self.get_uint(1);
fn Node CallView.get_arg(CallView self, uint i) => self.get_at(2, i);

typedef IfView = inline View;

fn Node IfView.condition(IfView self) => self.get(0);
fn Node IfView.then_block(IfView self) => self.get(1);
fn Node IfView.else_block(IfView self) => self.get(2);

typedef IdentView = inline View;
fn String IdentView.name(self, StringPool* pool) => pool.get((StringHandle)self.get_extra_index());

typedef LiteralView = inline View;
fn String LiteralView.value(LiteralView self, StringPool* pool)
{
	uint sh = self.ast.extra_indices[(Size)self.handle];
	return pool.get((StringHandle)sh);
}


// / ------------
