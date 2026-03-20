module test::new;

import std::io;

// my comment
alias MyBasicType = uint;
alias MyListType = List{ float };
alias MyFunctionPointer = fn String(char arg1, float arg2);

typedef MyType = float;

float my_first_global_var;
uint my_global_variable = -10 * 2;

<*
	brrrrrrrrrrrrrrrrrrp
	@param value
	@inline
*>
fn void parse(uint value)
{
	return 1 + 5 * 10;
}

fn int foo(uint value)
{
	defer (catch err)
	{
		return value > 5 ? 5 : 1;
	}

	defer {
		parse(2);
	}

}

fn String foo2(uint value)
{
	return "Do you know tha way?";
}

void* type;

module foo::bar;

import std::io;

fn void test(char arg) @inline
{
}
 