module c3_parser::ast::views;

import string_pool;
import c3_parser::common;
import lexer;

constdef BinaryViewFields : inline uint
{
	LEFT = 0,
	RIGHT,
	OP,
}
typedef BinaryView = inline View;
fn Node BinaryView.left(BinaryView self) => self.get(BinaryViewFields.LEFT);
fn Node BinaryView.right(BinaryView self) => self.get(BinaryViewFields.RIGHT);
fn TokenKind BinaryView.op(BinaryView self) => (TokenKind)self.get_uint(BinaryViewFields.OP);

constdef TernaryViewFields : inline uint
{
	CONDITION = 0,
	THEN_EXPR,
	ELSE_EXPR,
}
typedef TernaryView = inline View;
fn Node TernaryView.condition(self) => self.get(TernaryViewFields.CONDITION);
fn Node TernaryView.then_expr(self) => self.get(TernaryViewFields.THEN_EXPR);
fn Node TernaryView.else_expr(self) => self.get(TernaryViewFields.ELSE_EXPR);

constdef UnaryViewFields : inline uint
{
	OP = 0,
	RHS,
}
typedef UnaryView = inline View;
fn TokenKind UnaryView.op(self) => (TokenKind)self.get_uint(UnaryViewFields.OP);
fn Node UnaryView.rhs(self) => self.get(UnaryViewFields.RHS);

constdef CallViewFields : inline uint
{
	CALLEE = 0,
	TYPE_ARG,
	ARG,
	COMPOUND,
}
typedef CallView = inline View;
fn Node CallView.callee(self) => self.get(CallViewFields.CALLEE);
fn uint CallView.type_arg_count(self) => self.get_list_count(CallViewFields.TYPE_ARG);
fn Node CallView.get_type_arg(self, uint i) => self.get_list_item(CallViewFields.TYPE_ARG, i);
fn uint CallView.arg_count(self) => self.get_list_count(CallViewFields.ARG);
fn Node CallView.get_arg(self, uint i) => self.get_list_item(CallViewFields.ARG, i);
fn Node CallView.get_compound(self) => self.get(CallViewFields.COMPOUND);

constdef IfViewFields : inline uint
{
	CONDITION = 0,
	LABEL,
	THEN_BLOCK,
	ELSE_BLOCK,
}
typedef IfView = inline View;

fn Node IfView.condition(IfView self) => self.get(IfViewFields.CONDITION);
fn Node IfView.then_block(IfView self) => self.get(IfViewFields.THEN_BLOCK);
fn Node IfView.else_block(IfView self) => self.get(IfViewFields.ELSE_BLOCK);

typedef IdentView = inline View;
fn String IdentView.name(self, StringPool* pool) => pool.get((StringHandle)self.get_extra_index());

typedef LiteralView = inline View;
fn String LiteralView.value(LiteralView self, StringPool* pool)
{
	uint sh = self.ast.extra_indices[(Size)self.handle];
	return pool.get((StringHandle)sh);
}

typedef ExprListView = inline View;
fn uint ExprListView.count(self) => self.get_list_count(0);
fn Node ExprListView.get_item(self, uint index) => self.get_list_item(0, index);

constdef LambdaViewFields : inline uint
{
	RETURN_TYPE,
	ATTRIBUTES,
	BODY,
}
typedef LambdaView = inline View;
