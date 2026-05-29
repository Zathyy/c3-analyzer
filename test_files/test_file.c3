module hello; 

<*
	Hello there
	@param [&in] a : "my param"
	@require a > 0 : ""
	@ensure return > 0 : ""
*>
fn int foo(int a) {}