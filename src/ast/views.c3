module c3_parser::ast;

import string_pool;
import c3_parser::common;
import lexer;

struct NodeView 
{
	NodeKind kind;
    uint token_idx; 
    uint extra_idx;
}

struct View 
{
    Ast* ast;
    Node handle;
}

fn Node View.get_extra_index(self) => (Node)self.ast.extra_indices[(usz)self.handle];

macro View.get(self, $offset)
{
    return (Node)self.ast.extra_data[(usz)self.ast.extra_indices[(usz)self.handle] + $offset];
}

macro View.get_uint(self, $offset)
{
    return (uint)self.ast.extra_data[(usz)self.ast.extra_indices[(usz)self.handle] + $offset];
}

macro View.get_at(self, $base_offset, index)
{
    usz pos = (usz)self.ast.extra_indices[(usz)self.handle] + $base_offset + index;
    return (Node)self.ast.extra_data[pos];
}

typedef LiteralView = inline View;

fn String LiteralView.value(LiteralView self, StringPool* pool)
{
    uint sh = self.ast.extra_indices[(usz)self.handle];
	return pool.get(sh);
}

typedef PathView = inline View;

fn uint PathView.len(PathView self) => self.get_uint(0);
fn uint PathView.get_string_handle(PathView self, uint index) => (uint)self.get_at(1, index);

fn String PathView.get_text(PathView self, uint index, StringPool* pool) 
{
    return pool.get(self.get_string_handle(index));
}

typedef ModuleView = inline View;
fn Node ModuleView.path(ModuleView self) => self.get(0);

typedef ImportView = inline View;
fn Node ImportView.path(ImportView self)  => self.get(0);

typedef ForView = inline View;

fn Node ForView.init(ForView self) => self.get(0);
fn Node ForView.cond(ForView self) => self.get(1);
fn Node ForView.inc(ForView self)  => self.get(2);
fn Node ForView.body(ForView self) => self.get(3);

typedef CompoundView = inline View;

fn uint CompoundView.len(CompoundView self) => self.get_uint(0);
fn Node CompoundView.get(CompoundView self, uint index) => self.get_at(1, index);

typedef FnView = inline View;

fn String FnView.name(FnView self, StringPool* pool)
{
	uint sh = self.get_uint(0);
	return pool.get(sh);
}

fn Node FnView.return_type(FnView self) => self.get(1);
fn uint FnView.param_count(FnView self) => self.get_uint(2);
fn Node FnView.body(FnView self)        => self.get(3);
fn Node FnView.get_param(FnView self, uint index) => self.get_at(4, index);

typedef ParamView = inline View;

fn Node ParamView.get_type(ParamView self) => self.get(0);
fn String ParamView.get_name(ParamView self, StringPool* pool)
{	
	uint sh = self.get_uint(1);
	return pool.get(sh);
}

typedef TypeView = inline View;

fn String TypeView.name(TypeView self, StringPool* pool)
{
	uint sh = self.get_uint(0);
	return pool.get(sh);
}
//num of pointers *
fn Node TypeView.array_size(TypeView self) => self.get(1);
fn bool TypeView.is_vector(TypeView self) => self.get_flags().is_vector;
fn uint TypeView.ptr_count(TypeView self) => self.get_flags().ptr_count;
fn uint TypeView.gen_count(TypeView self) => self.get_flags().gen_count;
fn TypeFlags TypeView.get_flags(TypeView self) => (TypeFlags)self.get(2);
// Get a specific generic argument (e.g. the 'int' in 'List{int}')
fn Node TypeView.get_gen_arg(TypeView self, uint index) 
{
    return self.get_at(3, index);
}

typedef AliasView = inline View;
fn String AliasView.name(AliasView self, StringPool* pool) => pool.get(self.get_uint(0));
fn Node AliasView.target_type(AliasView self) => self.get(1);

typedef TypedefView = inline View;
fn String TypedefView.name(TypedefView self, StringPool* pool) => pool.get(self.get_uint(0));
fn Node TypedefView.base_type(TypedefView self) => self.get(1);

typedef GlobalView = inline View;

fn GlobalFlags GlobalView.flags(GlobalView self) => (GlobalFlags)self.get_uint(0);
fn String GlobalView.name(GlobalView self, StringPool* pool) => pool.get(self.get_uint(1));
fn Node GlobalView.type_node(GlobalView self) => self.get(2);
fn Node GlobalView.init_expr(GlobalView self) => self.get(3);

typedef VarDeclView = inline View;
fn String VarDeclView.name(self, StringPool* pool) => pool.get(self.get_uint(0));
fn Node VarDeclView.type_node(self) => self.get(1);
fn Node VarDeclView.init_expr(self) => self.get(2);

/// --- STMT ---

typedef ReturnView = inline View;
fn Node ReturnView.expr(self) => self.get_extra_index();

typedef DeferView = inline View;
fn Node DeferView.expr(self) => self.get_extra_index();

typedef ExprStmtView = inline View;
fn Node ExprStmtView.expr(self) => self.get_extra_index();

/// ------------

/// --- EXPR ---

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
fn String IdentView.name(self, StringPool* pool) => pool.get((uint)self.get_extra_index());

/// ------------