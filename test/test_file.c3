module test::new;

import std::io;

// my comment
alias MyBasicType = uint;
alias MyListType = List{ float };

typedef MyType = float;

uint my_global_variable;

<*
	brrrrrrrrrrrrrrrrrrp
	@param value
	@inline
*>
fn void parse(uint value)
{
	return 1 + 5 * 10;
}

<*
	test errors
*>
fn int foo(uint value)
{
	defer (catch err)
	{

	}

	defer {
		parse(2);
	}

}

<*
	test errors
*>
fn String foo2(uint value)
{
	return "Do you know tha way?";
}

void* type;


module foo::bar;

import std::io;

fn void test(char arg)
{
}
 