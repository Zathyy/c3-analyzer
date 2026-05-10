module c3_parser::ast::views;

import string_pool;
import c3_parser::common;
import lexer;

constdef ParamViewFields : inline uint
{
	NAME = 0,
	TYPE,
	INIT,
	FLAGS,
}
typedef ParamView = inline View;
fn String ParamView.name(ParamView self, StringPool* pool) => pool.get((StringHandle)self.get_uint(ParamViewFields.NAME));
fn Node ParamView.type_node(ParamView self) => self.get(ParamViewFields.TYPE);
fn Node ParamView.init_expr(ParamView self) => self.get(ParamViewFields.INIT);
fn bool ParamView.is_ref(ParamView self) => self.get_uint(ParamViewFields.FLAGS) != 0;

constdef ParamsListViewFields : inline uint
{
	PARAMS = 0,
}
typedef ParamsListView = inline View;
fn uint ParamsListView.count(self) => self.get_list_count(ParamsListViewFields.PARAMS);
fn ParamView ParamsListView.get_param(self, uint index) 
{
    return { self.ast, self.get_list_item(ParamsListViewFields.PARAMS, index) };
}

constdef BodyParamViewFields : inline uint
{
    NAME = 0,
    INNER_PARAMS
}
typedef BodyParamView = inline View; 
fn String BodyParamView.name(self, StringPool* pool) 
{
	return pool.get((StringHandle)self.get_uint(BodyParamViewFields.NAME));
}
fn ParamsListView BodyParamView.inner_params(self) 
{
    Node list_handle = self.get(BodyParamViewFields.INNER_PARAMS);
    return { self.ast, list_handle };
}

constdef AttributeListViewFields : inline uint
{
	ATTRIBUTES = 0,
}

typedef AttributeListView = inline View;
fn uint AttributeListView.count(self) => self.get_list_count(0);
fn Node AttributeListView.get_attr(self, uint index) => self.get_list_item(0, index);

constdef AttributeViewFields : inline uint
{
	KIND = 0,
	ARGS,
}
// The view for a single @attr(args)
typedef AttributeView = inline View;
fn AttributeKind AttributeView.kind(self) => (AttributeKind)self.get_uint(AttributeViewFields.KIND);
fn uint AttributeView.arg_count(self) => self.get_uint(AttributeViewFields.ARGS);
fn Node AttributeView.get_arg(self, uint index)
{
    uint base = self.get_uint(AttributeViewFields.ARGS);
    return (Node)self.ast.extra_data[(Size)base + index];
}

typedef PathView = inline View;
fn uint PathView.len(self) => self.get_uint(0);
fn StringHandle PathView.get_string_handle(self, uint index) 
    => (StringHandle)self.get_at(1, index);

fn String PathView.get_full(self, StringPool* pool)
{
	uint len = self.len();

	String result = "";
	for (uint i = 0; i < len; i++)
	{
		StringHandle sh = self.get_string_handle(i);
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

constdef TypeViewFields : inline uint
{
	NAME = 0,
	PTR_COUNT,
	ARRAY_SIZE,
	GENERICS,
	BASE_EXPR,
	FLAGS,
}
typedef TypeView = inline View;

fn String TypeView.name(TypeView self, StringPool* pool)
{
	uint sh = self.get_uint(TypeViewFields.NAME);
	return pool.get((StringHandle)sh);
}

fn uint TypeView.ptr_count(TypeView self) => self.get_uint(TypeViewFields.PTR_COUNT);

// 0 in this case does not equal invalid it means infered size '[*]'
fn Node TypeView.array_size(TypeView self) => self.get(TypeViewFields.ARRAY_SIZE);
fn uint TypeView.gen_count(TypeView self) => self.get_uint(TypeViewFields.GENERICS);
fn TypeFlags TypeView.get_flags(TypeView self) => (TypeFlags)self.get(TypeViewFields.FLAGS);
fn bool TypeView.is_vector(TypeView self) => self.get_flags().is_vector;
fn Node TypeView.get_gen_arg(TypeView self, uint index)
{
	uint base = self.get_uint(TypeViewFields.GENERICS);
	return (Node)self.ast.extra_data[(Size)base + index];
}

constdef FnTypeViewFields : inline uint
{
	RETURN_TYPE,
	PARAMS
}
typedef FnTypeView = inline View;

// The container for the whole <T, V> block
typedef GenericParamsView = inline View;
fn uint GenericParamsView.count(self) => self.ast.extra_data[(Size)self.get_extra_index()];
fn Node GenericParamsView.get_param(self, uint index) => (Node)self.ast.extra_data[(Size)self.get_extra_index() + 1 + index];

// The individual parameter T
typedef GenericParamView = inline View;
fn String GenericParamView.name(self, StringPool* pool) => pool.get((StringHandle)self.get_uint(0));
fn bool GenericParamView.is_variadic(self) => (self.get_uint(1) & 1) != 0;

constdef MacroParamsViewFields : inline uint
{
	PARAMS,
	BODY_PARAMS
}
typedef MacroParamsView = inline View;
fn ParamsListView MacroParamsView.params(self) 
{ 
	return { self.ast, self.get(MacroParamsViewFields.PARAMS) };
}

fn bool MacroParamsView.has_body(self)
{
	return self.get(MacroParamsViewFields.BODY_PARAMS).is_valid();
}

fn BodyParamView MacroParamsView.body_params(self) 
{
    Node body_node = self.get(MacroParamsViewFields.BODY_PARAMS);
    if (!body_node.is_valid()) return {};
    return { self.ast, body_node };
}

constdef LocalViewFields : inline uint
{
	NAME = 0,
	TYPE,
	INIT,
	ATTRIBUTES,
}
typedef LocalView = inline View;
