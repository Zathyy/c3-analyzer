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
		parse((int)value);
	}

	float my_local_var;

	int value_as_int = (int)value;

	if (value_as_int > 0 && value_as_int <= 10) 
	{

	}
	else if (value_as_int)
	{

	}
	else
	{

	}
}

fn String foo2(uint value)
{
	return "Do you know tha way?";
}

fn int foo3(uint value)
{
    int a = 55 * 8 / 5 * 3;

	int b = (55 * 8) / (5 * 3);

	int c = 55 * 8 - 1 / 5 * 3 - 1;

	int d = (55 * 8) - ((1 / 5) * 3) - 1; 
}

void* type;

module foo::bar;

import std::io;

fn void test(char arg) @inline
{
}
 