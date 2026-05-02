module c3_parser::ast::views;

import string_pool;
import c3_parser::common;
import lexer;

typedef ModuleView = inline View;
fn Node ModuleView.path(self) => self.get(0);
fn uint ModuleView.generics_offset(self) => self.get_uint(1);
fn uint ModuleView.attributes_offset(self) => self.get_uint(2);
fn bool ModuleView.is_generic(self) => self.generics_offset() != 0;
fn bool ModuleView.is_private(self) => self.has_attribute(self.attributes_offset(), AttributeKind.PRIVATE);
fn bool ModuleView.is_local(self) => self.has_attribute(self.attributes_offset(), AttributeKind.LOCAL);
fn GenericParamsView ModuleView.generics(self) 
{
    return (GenericParamsView){ self.ast, (Node)self.generics_offset() };
}

typedef ImportView = inline View;
fn Node ImportView.path(self) => self.get(0);
fn uint ImportView.attributes_offset(self) => self.get_uint(1);
fn bool ImportView.is_public(self) => self.has_attribute(self.attributes_offset(), AttributeKind.PUBLIC);

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
fn VarDeclFlags VarDeclView.flags(self) => (VarDeclFlags)self.get_uint(4);
fn bool VarDeclView.is_extern(self) => self.flags().is_extern;
fn bool VarDeclView.is_const(self)  => self.flags().is_const;

// inline keyword as a local variable
fn bool VarDeclView.is_inline(self)  => self.flags().is_inline;
fn bool VarDeclView.is_local(self)  => self.flags().is_local;
fn bool VarDeclView.is_thread_local(self)  => self.flags().is_thread_local;
fn bool VarDeclView.is_global(self) => !self.is_local();

typedef StructView = inline View;
fn String StructView.name(self, StringPool* pool) => pool.get((StringHandle)self.get_uint(0));
fn Node StructView.interface_offset(self) => self.get(1);
fn uint StructView.generic_params(self) => self.get_uint(2);
fn uint StructView.field_count(self) => self.get_list_count(3);
fn Node StructView.field(self, uint i) => self.get_list_item(3, i);

typedef FieldView = inline View;
fn String FieldView.name(self, StringPool* pool) => pool.get((StringHandle)self.get_uint(0));
fn Node FieldView.type_node(self) => self.get(1);

typedef EnumView = inline View;
fn String EnumView.name(self, StringPool* pool) => pool.get((StringHandle)self.get_uint(0));
fn Node EnumView.base_type(self) => self.get(1);
fn uint EnumView.params_offset(self) => self.get_uint(2);
fn uint EnumView.attributes_offset(self) => self.get_uint(3);

fn uint EnumView.member_count(self) => self.get_list_count(4);
fn Node EnumView.get_member(self, uint index) => self.get_list_item(4, index);

fn uint EnumView.flags(self) => self.get_uint(5);
fn bool EnumView.is_const_def(self) => (self.flags() & (1 << 0)) != 0;
fn bool EnumView.is_inline(self)    => (self.flags() & (1 << 1)) != 0;

typedef ContractView = inline View;
fn uint ContractView.requires_count(self) => self.get_list_count(0);
fn uint ContractView.ensures_count(self) => self.get_list_count(1);

fn ContractEntryView ContractView.get_req(self, uint index) 
{
	Node entry = self.get_list_item(0, index);
	return (ContractEntryView){ self.ast, entry };
}

fn ContractEntryView ContractView.get_ensure(self, uint index) 
{
	Node entry = self.get_list_item(1, index);
	return (ContractEntryView){ self.ast, entry };
}

typedef ContractEntryView = inline View;
fn Node ContractEntryView.condition(self) => self.get(0);
fn Node ContractEntryView.message(self) => self.get(1);
fn bool ContractEntryView.has_message(self) => self.message().is_valid();