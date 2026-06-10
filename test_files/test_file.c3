module hello;

fn void foo()
{
	defer io::printn("");
	defer io::print("A");
	defer try io::print("X");
	defer catch io::print("B");
	defer (catch err)
	 io::printf("%s", err);
	defer
	{
		defer (catch err)
		 io::printf("%s", err);
	}
}
