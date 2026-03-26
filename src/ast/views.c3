module c3_parser::ast;

import string_pool;

// Views is a way to index into each node without having to do index calculations everytime
// and provides an easy & safe way to access each nodes subnodes/data

struct PathView {
    Ast* ast;
    Node handle;
}

fn uint PathView.len(PathView self) => self.ast.extra_data[self.ast.extra_indices[(usz)self.handle]];

// String intern handle
fn uint PathView.get_string_handle(PathView self, uint index) 
{
    uint base = self.ast.extra_indices[(usz)self.handle];
    return self.ast.extra_data[(usz)base + 1 + index];
}

// String text for printing
fn String PathView.get_text(PathView self, uint index, StringPool* pool) {
    uint sh = self.get_string_handle(index);
    return pool.get(sh);
}

// ---

struct ModuleView 
{
    Ast* ast;
    Node handle;
}

// Returns the Node index of the PATH associated with this module
fn Node ModuleView.path(ModuleView self) 
{
    uint ex = self.ast.extra_indices[(usz)self.handle];
    return (Node)ex;
}

// ---

struct ImportView 
{
    Ast* ast;
    Node handle;
}

// Returns the Node index of the PATH associated with this import
fn Node ImportView.path(ImportView self) 
{
    uint ex = self.ast.extra_indices[(usz)self.handle];
    return (Node)ex;
}

// ---

struct ForView
{
    Ast* ast;
    Node handle;
}

fn Node ForView.init(ForView self) => (Node)self.ast.extra_data[(usz)self.ast.extra_indices[(usz)self.handle] + 0];
fn Node ForView.cond(ForView self) => (Node)self.ast.extra_data[(usz)self.ast.extra_indices[(usz)self.handle] + 1];
fn Node ForView.inc(ForView self)  => (Node)self.ast.extra_data[(usz)self.ast.extra_indices[(usz)self.handle] + 2];
fn Node ForView.body(ForView self) => (Node)self.ast.extra_data[(usz)self.ast.extra_indices[(usz)self.handle] + 3];

struct CompoundView 
{
    Ast* ast;
    Node handle;
}

fn uint CompoundView.len(CompoundView self) => self.ast.extra_data[(usz)self.ast.extra_indices[(usz)self.handle]];
fn Node CompoundView.get(CompoundView self, uint index) 
{
    uint base = self.ast.extra_indices[(usz)self.handle];
    return (Node)self.ast.extra_data[(usz)base + 1 + index];
}