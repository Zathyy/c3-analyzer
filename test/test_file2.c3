module foo::bar;

import std::io;

alias MyType = uint;

typedef MyOtherType = bool;

tlocal bool my_var;

fn void test(int foo, void* bar)
{
	if (foo > 5 && foo < 10)
	{
		defer (catch err) {

		}

		defer try io::print("");
		defer catch io::print("");
		return;
	}
	else if (foo < 0)
	{

	}
	else
	{

	}
}

struct Foo
{
	uint a;
	uint b;
}