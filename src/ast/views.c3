module c3_parser::ast;

import string_pool;

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
fn uint TypeView.ptr_count(TypeView self) => self.get_uint(1);
fn Node TypeView.array_size(TypeView self) => self.get(2);
// get number of generics
fn uint TypeView.gen_count(TypeView self) => self.get_uint(3);

// Get a specific generic argument (e.g. the 'int' in 'List{int}')
fn Node TypeView.get_gen_arg(TypeView self, uint index) 
{
    return self.get_at(4, index);
}