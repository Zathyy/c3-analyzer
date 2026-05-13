module c3_parser::ast::views;

import string_pool;
import c3_parser::common;
import lexer;

constdef ModuleViewFields : inline uint
{
	PATH = 0,
	GENERICS,
	ATTRIBUTES,
	CONTRACT,
}
typedef ModuleView = inline View;
fn Node ModuleView.path(self) => self.get(ModuleViewFields.PATH);
fn AttributeListView ModuleView.attributes(self)
{
	return { self.ast, self.get(ModuleViewFields.ATTRIBUTES) };
}
fn Node ModuleView.contract_node(self) => self.get(ModuleViewFields.CONTRACT);
fn bool ModuleView.has_contract(self) => self.contract_node().is_valid();
fn GenericDeclView ModuleView.generics(self) 
{
    return { self.ast, self.get(ModuleViewFields.GENERICS) };
}
fn bool ModuleView.is_generic(self) => self.generics().parameters_count() != 0;

constdef ImportViewFields : inline uint
{
	PATH = 0,
	ATTRIBUTES,
}
typedef ImportView = inline View;
fn Node ImportView.path(self) => self.get(ImportViewFields.PATH);
fn AttributeListView ImportView.attributes(self)
{
	return { self.ast, self.get(ImportViewFields.ATTRIBUTES) };
}

constdef InterfaceViewFields : inline uint
{
	NAME = 0,
	PARENTS,
	ATTRIBUTES,
	METHODS,
}
typedef InterfaceImplView = inline View;
fn uint InterfaceImplView.count(self) => self.ast.extra_data[(Size)self.get_extra_index()];
fn Node InterfaceImplView.get_type(self, uint index) => (Node)self.ast.extra_data[(Size)self.get_extra_index() + 1 + index];

constdef MacroViewFields : inline uint
{
	NAME = 0,
	ASSOCIATED,
	RETURN_TYPE,
	ATTRIBUTES,
	PARAMS,
	GENERICS,
	CONTRACT, 
	BODY,
}

constdef FnViewFields : inline uint
{
	NAME = 0,
	ASSOCIATED,
	RETURN_TYPE,
	ATTRIBUTES,
	PARAMS,
	GENERICS,
	CONTRACT,
	BODY,
}
typedef FnView = inline View;
fn String FnView.name(FnView self, StringPool* pool) => pool.get((StringHandle)self.get_uint(FnViewFields.NAME));
fn Node FnView.associated(FnView self) => self.get(FnViewFields.ASSOCIATED);
fn Node FnView.return_type(FnView self) => self.get(FnViewFields.RETURN_TYPE);
fn AttributeListView FnView.attributes(FnView self)
{
	return { self.ast, self.get(FnViewFields.ATTRIBUTES) };
}
fn Node FnView.body(FnView self) => self.get(FnViewFields.BODY);
fn ParamsListView FnView.params(self)
{
	return { self.ast, self.get(FnViewFields.PARAMS) };
}

constdef TypeAliasViewFields : inline uint
{
	NAME = 0,
	TARGET_TYPE,
	GENERICS,
	ATTRIBUTES,
	TYPE_ATTRIBUTES,
}
typedef TypeAliasView = inline View;
fn String TypeAliasView.name(self, StringPool* pool) => pool.get((StringHandle)self.get_uint(TypeAliasViewFields.NAME));
fn Node TypeAliasView.target_type(self) => self.get(TypeAliasViewFields.TARGET_TYPE);

constdef ExprAliasViewFields : inline uint
{
	NAME = 0,
	EXPR,
	ATTRIBUTES,
}
typedef ExprAliasView = inline View;
fn String ExprAliasView.name(self, StringPool* pool) => pool.get((StringHandle)self.get_uint(ExprAliasViewFields.NAME));
fn Node ExprAliasView.expr(self) => self.get(ExprAliasViewFields.EXPR);

constdef PathAliasViewFields : inline uint
{
	NAME = 0,
	PATH,
	ATTRIBUTES,
}
typedef PathAliasView = inline View;
fn String PathAliasView.name(self, StringPool* pool) => pool.get((StringHandle)self.get_uint(PathAliasViewFields.NAME));
fn Node PathAliasView.path(self) => self.get(PathAliasViewFields.PATH);

constdef TypedefViewFields : inline uint
{
	NAME = 0,
	BASE_TYPE,
	ATTRIBUTES,
	INTERFACES,
	GENERICS,
	TYPE_ATTRIBUTES,
}
typedef TypedefView = inline View;
fn String TypedefView.name(TypedefView self, StringPool* pool) => pool.get((StringHandle)self.get_uint(TypedefViewFields.NAME));
fn Node TypedefView.base_type(TypedefView self) => self.get(TypedefViewFields.BASE_TYPE);

constdef AttrdefViewFields : inline uint
{
	NAME = 0,
	PARAMS,
	ATTRIBUTES,
	VAL_ATTRIBUTES,
}
typedef AttrdefView = inline View;

constdef VarDeclViewFields : inline uint
{
	NAME = 0,
	TYPE,
	INIT,
	ATTRIBUTES,
	FLAGS,
}
typedef VarDeclView = inline View;
fn String VarDeclView.name(self, StringPool* pool) => pool.get((StringHandle)self.get_uint(VarDeclViewFields.NAME));
fn Node VarDeclView.type_node(self) => self.get(VarDeclViewFields.TYPE);
fn Node VarDeclView.init_expr(self) => self.get(VarDeclViewFields.INIT);
fn AttributeListView VarDeclView.attributes(self)
{
	return { self.ast, self.get(VarDeclViewFields.ATTRIBUTES) };
}
// meta information
fn VarDeclFlags VarDeclView.flags(self) => (VarDeclFlags)self.get_uint(VarDeclViewFields.FLAGS);
fn bool VarDeclView.is_extern(self) => self.flags().is_extern;
fn bool VarDeclView.is_const(self)  => self.flags().is_const;

// inline keyword as a local variable
fn bool VarDeclView.is_inline(self)  => self.flags().is_inline;
fn bool VarDeclView.is_local(self)  => self.flags().is_local;
fn bool VarDeclView.is_thread_local(self)  => self.flags().is_thread_local;
fn bool VarDeclView.is_global(self) => !self.is_local();

constdef StructViewFields : inline uint
{
	NAME = 0,
	INTERFACES,
	GENERICS,
	ATTRIBUTES,
	FIELDS,
	CONTRACT,
}
typedef StructView = inline View;
fn String StructView.name(self, StringPool* pool) => pool.get((StringHandle)self.get_uint(StructViewFields.NAME));
fn Node StructView.interface_offset(self) => self.get(StructViewFields.INTERFACES);
fn uint StructView.generic_params(self) => self.get_uint(StructViewFields.GENERICS);
fn uint StructView.field_count(self) => self.get_list_count(StructViewFields.FIELDS);
fn Node StructView.field(self, uint i) => self.get_list_item(StructViewFields.FIELDS, i);

constdef BitstructViewFields : inline uint
{
	NAME = 0,
	INTERFACES,
	TYPE,
	ATTRIBUTES,
	FIELDS,
}
typedef BitstructView = inline View;

constdef BitstructFieldViewFields : inline uint
{
	NAME = 0,
	TYPE,
	START_BIT,
	END_BIT,
	ATTRIBUTES,
}
typedef BitstructFieldView = inline View;

constdef FieldViewFields : inline uint
{
	NAME = 0,
	TYPE,
	ATTRIBUTES,
	FLAGS,
}
typedef FieldView = inline View;
fn String FieldView.name(self, StringPool* pool) => pool.get((StringHandle)self.get_uint(FieldViewFields.NAME));
fn Node FieldView.type_node(self) => self.get(FieldViewFields.TYPE);
fn uint FieldView.flags(self) => self.get_uint(FieldViewFields.FLAGS);
fn bool FieldView.is_inline(self) => (self.flags() & (1 << 0)) != 0;

constdef EnumViewFields : inline uint
{
	NAME = 0,
	BASE_TYPE,
	PARAMS,
	ATTRIBUTES,
	CONTRACT,
	MEMBERS,
	FLAGS,
}
typedef EnumView = inline View;
fn String EnumView.name(self, StringPool* pool) => pool.get((StringHandle)self.get_uint(EnumViewFields.NAME));
fn Node EnumView.base_type(self) => self.get(EnumViewFields.BASE_TYPE);
fn uint EnumView.params_offset(self) => self.get_uint(EnumViewFields.PARAMS);
fn AttributeListView EnumView.attributes(self)
{
	return { self.ast, self.get(EnumViewFields.ATTRIBUTES) };
}

fn uint EnumView.member_count(self) => self.get_list_count(EnumViewFields.MEMBERS);
fn Node EnumView.get_member(self, uint index) => self.get_list_item(EnumViewFields.MEMBERS, index);

fn uint EnumView.flags(self) => self.get_uint(EnumViewFields.FLAGS);
fn bool EnumView.is_const_def(self) => (self.flags() & (1 << 0)) != 0;
fn bool EnumView.is_inline(self)    => (self.flags() & (1 << 1)) != 0;

constdef EnumMemberViewFields : inline uint
{
	NAME = 0,
	ATTRIBUTES,
	EXPLICIT_VALUE,
	ASSOCIATED,
}

constdef ContractViewFields : inline uint
{
	REQUIRES = 0,
	ENSURES,
	PARAMS,
	OPTIONAL_RETURNS,
	RETURN,
	FLAGS,
	DEPRECATED,
}
typedef ContractView = inline View;
fn uint ContractView.requires_count(self) => self.get_list_count(ContractViewFields.REQUIRES);
fn uint ContractView.ensures_count(self) => self.get_list_count(ContractViewFields.ENSURES);
fn uint ContractView.params_count(self) => self.get_list_count(ContractViewFields.PARAMS);
fn uint ContractView.optional_returns_count(self) => self.get_list_count(ContractViewFields.OPTIONAL_RETURNS);

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

fn ContractEntryView ContractView.get_param(self, uint index)
{
	Node entry = self.get_list_item(2, index);
	return (ContractEntryView){ self.ast, entry };
}

fn ContractEntryView ContractView.get_optional_return(self, uint index)
{
	Node entry = self.get_list_item(3, index);
	return (ContractEntryView){ self.ast, entry };
}

constdef ContractEntryViewFields : inline uint
{
	CONDITION = 0,
	MESSAGE,
}
typedef ContractEntryView = inline View;
fn Node ContractEntryView.condition(self) => self.get(ContractEntryViewFields.CONDITION);
fn Node ContractEntryView.message(self) => self.get(ContractEntryViewFields.MESSAGE);
fn bool ContractEntryView.has_message(self) => self.message().is_valid();

constdef GenericDeclViewFields : inline uint
{
	PARAMETERS = 0,
}
typedef GenericDeclView = inline View;
fn uint GenericDeclView.parameters_count(self)
{
	if (!self.handle.is_valid()) return 0;
	return self.get_list_count(GenericDeclViewFields.PARAMETERS);
}
fn String GenericDeclView.get_parameter(self, StringPool* pool, uint index)
{
	Node item = self.get_list_item(GenericDeclViewFields.PARAMETERS, index);
	return pool.get((StringHandle)item);
}

constdef FaultdefDeclViewFields : inline uint
{
	FAULTS = 0,
	ATTRIBUTES,
}
typedef FaultdefDeclView = inline View;
