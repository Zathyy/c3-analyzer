module test::new;

import std::io;

fn void parse(uint value)
{
	io::printn("foo");
}

<*
	test errors
*>
fn int int foo(uint value)
{
	return 0;
}

void* type;


module foo::bar;

import std::io;

fn void test(char arg)
{
	io::printn("hello there");
	defer io::printn("do you know tha way");
}
 