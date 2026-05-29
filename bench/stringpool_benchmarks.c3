module parser_benchmarks;

import parser::ast;

const sz STRING_POOL_BENCH_COUNT           = 4096;
const sz STRING_POOL_BENCH_ARENA_PAGE_SIZE = 1 << 20;

sz string_pool_benchmark_sink;

struct StringPoolMemoryStats
{
	sz current;
	sz peak;
	sz total;
	sz allocations;
}

fn void configure_string_pool_benchmarks() @init @if(env::BENCHMARKING)
{
	set_benchmark_warmup_iterations(1);
	set_benchmark_max_iterations(50);
	set_benchmark_func_iterations("parser_benchmarks::benchmark_hash_string_pool_memory_usage", 1);
	set_benchmark_func_iterations("parser_benchmarks::benchmark_trie_string_pool_memory_usage", 1);
}

fn String[] make_string_pool_benchmark_strings(Allocator allocator)
{
	String[] strings = alloc::alloc_array(allocator, String, STRING_POOL_BENCH_COUNT);

	for (sz i = 0; i < STRING_POOL_BENCH_COUNT; i++)
	{
		strings[i] = string::format(
			allocator,
			"module_%04d.scope_%04d.symbol_%04d.variant_%04d",
			i,
			i % 257,
			i % 1021,
			i % 17
		);
	}

	return strings;
}

fn void free_string_pool_benchmark_strings(Allocator allocator, String[] strings)
{
	foreach (s : strings)
	{
		s.free(allocator);
	}

	alloc::free(allocator, strings);
}

fn void free_hash_string_pool_owned_strings(StringPool* pool)
{
	foreach (s : pool.stable_strings)
	{
		s.free(pool.allocator);
	}
}

fn StringPoolMemoryStats measure_hash_string_pool_memory(String[] strings)
{
	TrackingAllocator tracker;
	tracker.init(mem);
	defer tracker.free();

	StringPool pool;
	pool.init(&tracker, STRING_POOL_BENCH_COUNT);

	foreach (s : strings)
	{
		(void)pool.internalize(s);
	}

	StringPoolMemoryStats stats = {
		.current = tracker.allocated(),
		.peak = tracker.max_allocated(),
		.total = tracker.total_allocated(),
		.allocations = tracker.total_allocation_count(),
	};

	free_hash_string_pool_owned_strings(&pool);
	pool.free();
	assert(!tracker.has_leaks());
	return stats;
}

fn StringPoolMemoryStats measure_trie_string_pool_memory(String[] strings)
{
	TrackingAllocator tracker;
	tracker.init(mem);
	defer tracker.free();

	TrieStringPool pool;
	pool.init(&tracker, STRING_POOL_BENCH_COUNT);

	foreach (s : strings)
	{
		(void)pool.internalize(s);
	}

	StringPoolMemoryStats stats = {
		.current = tracker.allocated(),
		.peak = tracker.max_allocated(),
		.total = tracker.total_allocated(),
		.allocations = tracker.total_allocation_count(),
	};

	pool.free();
	assert(!tracker.has_leaks());

	return stats;
}

fn void log_string_pool_memory_stats(String label, StringPoolMemoryStats stats) @if(env::BENCHMARKING)
{
	@log_benchmark(
		"%s memory: current=%d bytes, peak=%d bytes, total=%d bytes, allocations=%d",
		label,
		stats.current,
		stats.peak,
		stats.total,
		stats.allocations
	);
}

fn void benchmark_hash_string_pool_insert() @benchmark
{
	String[] strings = make_string_pool_benchmark_strings(mem);
	DynamicArenaAllocator arena;
	arena.init(mem, STRING_POOL_BENCH_ARENA_PAGE_SIZE);

	StringPool pool;
	pool.init(&arena, STRING_POOL_BENCH_COUNT);

	sz checksum;
	@start_benchmark();
	foreach (s : strings)
	{
		checksum += pool.internalize(s);
	}
	@end_benchmark();

	@volatile_store(string_pool_benchmark_sink, checksum);
	arena.free();
	free_string_pool_benchmark_strings(mem, strings);
}

fn void benchmark_hash_string_pool_memory_usage() @benchmark
{
	String[] strings = make_string_pool_benchmark_strings(mem);

	@start_benchmark();
	StringPoolMemoryStats stats = measure_hash_string_pool_memory(strings);
	@end_benchmark();

	@volatile_store(string_pool_benchmark_sink, stats.peak);
	log_string_pool_memory_stats("hash", stats);
	free_string_pool_benchmark_strings(mem, strings);
}

fn void benchmark_trie_string_pool_memory_usage() @benchmark
{
	String[] strings = make_string_pool_benchmark_strings(mem);

	@start_benchmark();
	StringPoolMemoryStats stats = measure_trie_string_pool_memory(strings);
	@end_benchmark();

	@volatile_store(string_pool_benchmark_sink, stats.peak);
	log_string_pool_memory_stats("trie", stats);
	free_string_pool_benchmark_strings(mem, strings);
}

fn void benchmark_trie_string_pool_insert() @benchmark
{
	String[] strings = make_string_pool_benchmark_strings(mem);
	DynamicArenaAllocator arena;
	arena.init(mem, STRING_POOL_BENCH_ARENA_PAGE_SIZE);

	TrieStringPool pool;
	pool.init(&arena, STRING_POOL_BENCH_COUNT);

	sz checksum;
	@start_benchmark();
	foreach (s : strings)
	{
		checksum += pool.internalize(s);
	}
	@end_benchmark();

	@volatile_store(string_pool_benchmark_sink, checksum);
	arena.free();
	free_string_pool_benchmark_strings(mem, strings);
}

fn void benchmark_hash_string_pool_get() @benchmark
{
	String[] strings = make_string_pool_benchmark_strings(mem);
	DynamicArenaAllocator arena;
	arena.init(mem, STRING_POOL_BENCH_ARENA_PAGE_SIZE);

	StringPool pool;
	pool.init(&arena, STRING_POOL_BENCH_COUNT);
	foreach (s : strings) (void)pool.internalize(s);

	sz checksum;
	@start_benchmark();
	for (sz i = 0; i < STRING_POOL_BENCH_COUNT; i++)
	{
		checksum += pool.get(i)!!.len;
	}
	@end_benchmark();

	@volatile_store(string_pool_benchmark_sink, checksum);
	arena.free();
	free_string_pool_benchmark_strings(mem, strings);
}

fn void benchmark_trie_string_pool_get() @benchmark
{
	String[] strings = make_string_pool_benchmark_strings(mem);
	DynamicArenaAllocator arena;
	arena.init(mem, STRING_POOL_BENCH_ARENA_PAGE_SIZE);

	TrieStringPool pool;
	pool.init(&arena, STRING_POOL_BENCH_COUNT);
	foreach (s : strings) (void)pool.internalize(s);

	sz checksum;
	@start_benchmark();
	for (sz i = 0; i < STRING_POOL_BENCH_COUNT; i++)
	{
		checksum += pool.get(i)!!.len;
	}
	@end_benchmark();

	@volatile_store(string_pool_benchmark_sink, checksum);
	arena.free();
	free_string_pool_benchmark_strings(mem, strings);
}

fn void benchmark_hash_string_pool_contains_existing() @benchmark
{
	String[] strings = make_string_pool_benchmark_strings(mem);
	DynamicArenaAllocator arena;
	arena.init(mem, STRING_POOL_BENCH_ARENA_PAGE_SIZE);

	StringPool pool;
	pool.init(&arena, STRING_POOL_BENCH_COUNT);
	foreach (s : strings) (void)pool.internalize(s);

	sz checksum;
	@start_benchmark();
	foreach (s : strings)
	{
		if (pool.contains(s)) checksum++;
	}
	@end_benchmark();

	@volatile_store(string_pool_benchmark_sink, checksum);
	arena.free();
	free_string_pool_benchmark_strings(mem, strings);
}

fn void benchmark_trie_string_pool_contains_existing() @benchmark
{
	String[] strings = make_string_pool_benchmark_strings(mem);
	DynamicArenaAllocator arena;
	arena.init(mem, STRING_POOL_BENCH_ARENA_PAGE_SIZE);

	TrieStringPool pool;
	pool.init(&arena, STRING_POOL_BENCH_COUNT);
	foreach (s : strings) (void)pool.internalize(s);

	sz checksum;
	@start_benchmark();
	foreach (s : strings)
	{
		if (pool.contains(s)) checksum++;
	}
	@end_benchmark();

	@volatile_store(string_pool_benchmark_sink, checksum);
	arena.free();
	free_string_pool_benchmark_strings(mem, strings);
}

fn void benchmark_hash_string_pool_contains_missing() @benchmark
{
	String[] strings = make_string_pool_benchmark_strings(mem);
	DynamicArenaAllocator arena;
	arena.init(mem, STRING_POOL_BENCH_ARENA_PAGE_SIZE);

	StringPool pool;
	pool.init(&arena, STRING_POOL_BENCH_COUNT);
	foreach (s : strings) (void)pool.internalize(s);

	sz checksum;
	@start_benchmark();
	for (sz i = 0; i < STRING_POOL_BENCH_COUNT; i++)
	{
		if (!pool.contains("missing.symbol.name")) checksum++;
	}
	@end_benchmark();

	@volatile_store(string_pool_benchmark_sink, checksum);
	arena.free();
	free_string_pool_benchmark_strings(mem, strings);
}

fn void benchmark_trie_string_pool_contains_missing() @benchmark
{
	String[] strings = make_string_pool_benchmark_strings(mem);
	DynamicArenaAllocator arena;
	arena.init(mem, STRING_POOL_BENCH_ARENA_PAGE_SIZE);

	TrieStringPool pool;
	pool.init(&arena, STRING_POOL_BENCH_COUNT);
	foreach (s : strings) (void)pool.internalize(s);

	sz checksum;
	@start_benchmark();
	for (sz i = 0; i < STRING_POOL_BENCH_COUNT; i++)
	{
		if (!pool.contains("missing.symbol.name")) checksum++;
	}
	@end_benchmark();

	@volatile_store(string_pool_benchmark_sink, checksum);
	arena.free();
	free_string_pool_benchmark_strings(mem, strings);
}

fn void benchmark_hash_string_pool_duplicate_insert() @benchmark
{
	String[] strings = make_string_pool_benchmark_strings(mem);
	DynamicArenaAllocator arena;
	arena.init(mem, STRING_POOL_BENCH_ARENA_PAGE_SIZE);

	StringPool pool;
	pool.init(&arena, STRING_POOL_BENCH_COUNT);
	foreach (s : strings) (void)pool.internalize(s);

	sz checksum;
	@start_benchmark();
	foreach (s : strings)
	{
		checksum += pool.internalize(s);
	}
	@end_benchmark();

	@volatile_store(string_pool_benchmark_sink, checksum);
	arena.free();
	free_string_pool_benchmark_strings(mem, strings);
}

fn void benchmark_trie_string_pool_duplicate_insert() @benchmark
{
	String[] strings = make_string_pool_benchmark_strings(mem);
	DynamicArenaAllocator arena;
	arena.init(mem, STRING_POOL_BENCH_ARENA_PAGE_SIZE);

	TrieStringPool pool;
	pool.init(&arena, STRING_POOL_BENCH_COUNT);
	foreach (s : strings) (void)pool.internalize(s);

	sz checksum;
	@start_benchmark();
	foreach (s : strings)
	{
		checksum += pool.internalize(s);
	}
	@end_benchmark();

	@volatile_store(string_pool_benchmark_sink, checksum);
	arena.free();
	free_string_pool_benchmark_strings(mem, strings);
}
