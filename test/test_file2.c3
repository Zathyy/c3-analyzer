module example;

interface MyFirstInterface
{
	fn void foo();
}

interface MyInterface : MyFirstInterface
{
	fn void bar();
}

struct Bar (MyInterface)
{
	int placeholder;
}

fn void Bar.foo(&self) @dynamic
{
}

fn void Bar.bar(&self) @dynamic
{
}

int a = foo::get_value(arg0: 123, arg1: 534, null);
