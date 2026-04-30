module c3_parser::ast::views;

import string_pool;
import c3_parser::common;
import lexer;

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
fn Node CallView.callee(self) => self.get(0);
fn uint CallView.arg_count(self) => self.get_list_count(1);
fn Node CallView.get_arg(self, uint i) => self.get_list_item(1, i);

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

typedef ExprListView = inline View;
fn uint ExprListView.count(self) => self.get_list_count(0);
fn Node ExprListView.get_item(self, uint index) => self.get_list_item(0, index);