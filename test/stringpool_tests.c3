module parser_tests @test;

import parser::ast;

fn void test_string_pool_internalizes_unique_strings() @test
{
	StringPool pool;
	pool.init(mem, 8);
	defer pool.free();

	StringID first = pool.internalize("alpha");
	StringID second = pool.internalize("beta");
	StringID first_again = pool.internalize("alpha");

	assert(first == first_again);
	assert(first != second);
	assert(pool.get(first)!! == "alpha");
	assert(pool.get(second)!! == "beta");
}

fn void test_string_pool_contains_strings() @test
{
	StringPool pool;
	pool.init(mem, 8);
	defer pool.free();

	pool.internalize("romane");
	pool.internalize("romanus");
	pool.internalize("rubicon");

	assert(pool.contains("romane"));
	assert(pool.contains("romanus"));
	assert(pool.contains("rubicon"));
	assert(!pool.contains("roman"));
	assert(!pool.contains("missing"));
}

fn void test_string_pool_clear_resets_pool() @test
{
	StringPool pool;
	pool.init(mem, 8);
	defer pool.free();

	StringID before_clear = pool.internalize("before");
	assert(pool.contains("before"));
	assert(pool.get(before_clear)!! == "before");

	pool.clear();

	assert(!pool.contains("before"));

	StringID after_clear = pool.internalize("after");
	assert(after_clear == 0);
	assert(pool.get(after_clear)!! == "after");
}

fn void test_string_pool_free_releases_allocations() @test
{
	TrackingAllocator tracker;
	tracker.init(mem);
	defer tracker.free();

	StringPool pool;
	pool.init(&tracker, 8);

	pool.internalize("romane");
	pool.internalize("romanus");
	pool.internalize("rubens");
	pool.internalize("ruber");
	pool.internalize("rubicon");

	pool.free();
	assert(!tracker.has_leaks());
}
