module analyzer::workspace @if($feature(SEMA));

import analyzer::sema;
import analyzer::core;

import std::collections::list;

fn List{SymbolEntry}*? Workspace.lookup_method(&self, String type_name, String method_name) 
{
	foreach (mod : self.modules.value_iter()) 
	{
		if (try list = mod.registry.get_candidates(type_name, method_name)) 
		{
			return list;
		}
	}
	return null;
}