module parser_tests;

import parser::workspace;
import parser::ast;

import std::io;
import std::collections::list;
import std::io::file;
import std::io::path;

<*
 Write a C3 source string to a named temp file under /tmp/ and
 return the path.  Panics on I/O failure so tests fail fast.
*>
fn String write_fixture(String name, String content) @private
{
    String path = string::tformat("%s/c3_test_%s.c3", path::temp_directory(tmem)!!, name);
    File f = file::open(path, "w")!!;
    f.write(content)!!;
    (void)f.close()!!;
    return path;
}

<*
  Count how many top-level nodes inside this specific ModuleSection match a given kind.
*>
fn int count_kind(ModuleSection* s, NodeKind kind) @private
{
    int n = 0;
    
    foreach (node_ptr : s.nodes)
    {
        if (node_ptr == null) continue;
        
        // Directly check the node's kind field
        if (node_ptr.kind == kind) 
        {
            n++;
        }
    }
    return n;
}