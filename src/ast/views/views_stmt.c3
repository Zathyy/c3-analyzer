module c3_parser::ast::views;

import string_pool;
import c3_parser::common;
import lexer;

typedef ReturnView = inline View;
fn Node ReturnView.expr(self) => self.get_extra_index();

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
fn uint CompoundView.len(self) => self.ast.extra_data[(Size)self.get_extra_index()];
fn Node CompoundView.get(self, uint index) => (Node)self.ast.extra_data[(Size)self.get_extra_index() + 1 + index];

constdef CtAssertViewFields : inline uint
{
	COND = 0,
	MESSAGE,
	ARGS,
}
typedef CtAssertView = inline View;
fn Node CtAssertView.cond(self) => self.get(CtAssertViewFields.COND);
fn Node CtAssertView.message(self) => self.get(CtAssertViewFields.MESSAGE);
fn uint CtAssertView.get_args_count(self) => self.get_list_count(CtAssertViewFields.ARGS);
fn Node CtAssertView.get_arg(self, uint index) => self.get_list_item(CtAssertViewFields.ARGS, index);