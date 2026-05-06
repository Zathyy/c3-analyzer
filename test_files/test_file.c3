module bv;

import std::io;

<*
	@param $Type : "The type of the first element"
	@return "The first element"
	@return? TYPE_MISMATCH, NO_MORE_ELEMENT
*>
fn int sum(int a, int b) 
{
	return a + b; 
}