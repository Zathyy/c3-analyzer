module analyzer::sema @if($feature(SEMA));

import analyzer::core;

struct SymbolEntry
{
    Node* node;
	<* `@if(expr)` *>
    Node* condition;
	sz section_id;
}

