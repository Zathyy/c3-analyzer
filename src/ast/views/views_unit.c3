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

typedef AttributeListView = inline View;
fn uint AttributeListView.count(self) => self.get_list_count(0);
fn Node AttributeListView.get_attr(self, uint index) => self.get_list_item(0, index);

// The view for a single @attr(args)
typedef AttributeView = inline View;
fn AttributeKind AttributeView.kind(self) => (AttributeKind)self.get_uint(0);
fn uint AttributeView.arg_count(self) => self.get_uint(2);
fn Node AttributeView.get_arg(self, uint index)
{
    uint base = self.get_uint(1);
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

// The container for the whole <T, V> block
typedef GenericParamsView = inline View;
fn uint GenericParamsView.count(self) => self.ast.extra_data[(Size)self.get_extra_index()];
fn Node GenericParamsView.get_param(self, uint index) => (Node)self.ast.extra_data[(Size)self.get_extra_index() + 1 + index];

// The individual parameter T
typedef GenericParamView = inline View;
fn String GenericParamView.name(self, StringPool* pool) => pool.get((StringHandle)self.get_uint(0));
fn bool GenericParamView.is_variadic(self) => (self.get_uint(1) & 1) != 0;
