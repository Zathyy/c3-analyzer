module c3_parser::ast::views;

import string_pool;
import c3_parser::common;
import lexer;

typedef ModuleView = inline View;
fn Node ModuleView.path(self) => self.get(0);
fn Node ModuleView.generic(self) => self.get(1);
fn Node ModuleView.attribute(self) => self.get(2);

typedef ImportView = inline View;
fn Node ImportView.path(self) => self.get(0);
fn Node ImportView.attribute(self) => self.get(1);

typedef InterfaceImplView = inline View;
fn uint InterfaceImplView.count(self) => self.ast.extra_data[(Size)self.get_extra_index()];
fn Node InterfaceImplView.get_type(self, uint index) => (Node)self.ast.extra_data[(Size)self.get_extra_index() + 1 + index];

typedef FnView = inline View;
fn String FnView.name(FnView self, StringPool* pool) => pool.get((StringHandle)self.get_uint(0));
fn Node FnView.associated(FnView self) => self.get(1);
fn Node FnView.return_type(FnView self) => self.get(2);
fn uint FnView.attributes_offset(FnView self) => self.get_uint(3);
fn Node FnView.body(FnView self) => self.get(5);

fn bool FnView.is_inline(self) => self.has_attribute(3, AttributeKind.INLINE);
fn bool FnView.is_extern(self) => self.has_attribute(3, AttributeKind.EXTERN);

fn uint FnView.param_count(FnView self)
{
    uint offset = self.get_uint(4); // params index
    return self.ast.extra_data[(Size)offset];
}

fn Node FnView.get_param(FnView self, uint index)
{
    uint offset = self.get_uint(4);
    // [offset] is count, [offset + 1 + index] is the actual param Node
    return (Node)self.ast.extra_data[(Size)offset + 1 + index];
}

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
fn uint VarDeclView.attributes_offset(self) => self.get_uint(3);
// meta information
fn uint VarDeclView.flags(self) => self.get_uint(4);
fn bool VarDeclView.is_extern(self) => (self.flags() & (1 << 0)) != 0;
fn bool VarDeclView.is_const(self)  => (self.flags() & (1 << 1)) != 0;

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