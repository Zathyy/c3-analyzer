module bv;

import std::io;

<*
	my awesome contract

	@require a > 0 : "a not greater"
	@ensure return != 0 : "returned 0"
*>
fn int sum(int a, int b) 
{
	return a + b; 
}