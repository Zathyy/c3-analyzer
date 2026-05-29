module parser_tests @test;

import parser::trie;

fn void test_compressed_trie_contains_inserted_keys() @test
{
	CompressedTrie{int} trie;
	trie.init(mem);
	defer trie.free();

	assert(!trie.contains("car"));

	trie.insert("car", 1);
	trie.insert("cart", 2);
	trie.insert("cat", 3);

	assert(trie.contains("car"));
	assert(trie.contains("cart"));
	assert(trie.contains("cat"));
}

fn void test_compressed_trie_rejects_prefixes_and_extensions() @test
{
	CompressedTrie{int} trie;
	trie.init(mem);
	defer trie.free();

	trie.insert("cart", 1);

	assert(!trie.contains("car"));
	assert(!trie.contains("carts"));

	trie.insert("car", 2);

	assert(trie.contains("car"));
	assert(trie.contains("cart"));
}

fn void test_compressed_trie_gets_inserted_values() @test
{
	CompressedTrie{int} trie;
	trie.init(mem);
	defer trie.free();

	trie.insert("car", 1);
	trie.insert("cart", 2);
	trie.insert("cat", 3);

	assert(trie.get("car")!! == 1);
	assert(trie.get("cart")!! == 2);
	assert(trie.get("cat")!! == 3);
	assert(@catch(trie.get("ca")));
}

fn void test_compressed_trie_updates_existing_keys() @test
{
	CompressedTrie{int} trie;
	trie.init(mem);
	defer trie.free();

	trie.insert("car", 1);
	trie.insert("car", 42);

	assert(trie.contains("car"));
	assert(trie.get("car")!! == 42);
}

fn void test_compressed_trie_get_ref_returns_stored_value() @test
{
	CompressedTrie{int} trie;
	trie.init(mem);
	defer trie.free();

	trie.insert("cat", 3);

	int* value = trie.get_ref("cat")!!;
	*value = 30;

	assert(trie.get("cat")!! == 30);
	assert(*trie.get_ref("cat")!! == 30);
}

fn void test_compressed_trie_supports_empty_key() @test
{
	CompressedTrie{int} trie;
	trie.init(mem);
	defer trie.free();

	assert(!trie.contains(""));

	trie.insert("", 7);

	assert(trie.contains(""));
	assert(trie.get("")!! == 7);
}

fn void test_compressed_trie_handles_divergent_first_bytes() @test
{
	CompressedTrie{int} trie;
	trie.init(mem);
	defer trie.free();

	trie.insert("alpha", 1);
	trie.insert("beta", 2);
	trie.insert("gamma", 3);

	assert(trie.get("alpha")!! == 1);
	assert(trie.get("beta")!! == 2);
	assert(trie.get("gamma")!! == 3);
	assert(!trie.contains("delta"));
}

fn void test_compressed_trie_handles_deep_splits() @test
{
	CompressedTrie{int} trie;
	trie.init(mem);
	defer trie.free();

	trie.insert("romane", 1);
	trie.insert("romanus", 2);
	trie.insert("rubens", 3);
	trie.insert("ruber", 4);
	trie.insert("rubicon", 5);

	assert(trie.get("romane")!! == 1);
	assert(trie.get("romanus")!! == 2);
	assert(trie.get("rubens")!! == 3);
	assert(trie.get("ruber")!! == 4);
	assert(trie.get("rubicon")!! == 5);
	assert(!trie.contains("roman"));
	assert(!trie.contains("rub"));
}

fn void test_compressed_trie_frees_split_nodes_without_leaks() @test
{
	TrackingAllocator tracker;
	tracker.init(mem);
	defer tracker.free();

	CompressedTrie{int} trie;
	trie.init(&tracker);

	trie.insert("romane", 1);
	trie.insert("romanus", 2);
	trie.insert("rubens", 3);
	trie.insert("ruber", 4);
	trie.insert("rubicon", 5);
	trie.insert("alpha", 6);
	trie.insert("alphabet", 7);
	trie.insert("alpine", 8);
	trie.insert("beta", 9);
	trie.insert("betamax", 10);

	trie.insert("romane", 11);
	trie.insert("alphabet", 12);
	trie.insert("", 13);

	assert(trie.get("romane")!! == 11);
	assert(trie.get("alphabet")!! == 12);
	assert(trie.get("")!! == 13);

	trie.free();
	assert(!tracker.has_leaks());
}

fn void test_compressed_trie_sparse_children_keep_memory_small() @test
{
	TrackingAllocator tracker;
	tracker.init(mem);
	defer tracker.free();

	CompressedTrie{sz} trie;
	trie.init(&tracker);

	for (sz i = 0; i < 4096; i++)
	{
		String key = string::format(
			mem,
			"module_%04d.scope_%04d.symbol_%04d.variant_%04d",
			i,
			i % 257,
			i % 1021,
			i % 17
		);
		trie.insert(key, i);
		key.free(mem);
	}

	assert(tracker.max_allocated() < 4 * 1024 * 1024);

	trie.free();
	assert(!tracker.has_leaks());
}

fn void test_compressed_trie_handles_promoted_dense_children() @test
{
	TrackingAllocator tracker;
	tracker.init(mem);
	defer tracker.free();

	CompressedTrie{int} trie;
	trie.init(&tracker);

	trie.insert("a_symbol", 1);
	trie.insert("b_symbol", 2);
	trie.insert("c_symbol", 3);
	trie.insert("d_symbol", 4);
	trie.insert("e_symbol", 5);
	trie.insert("f_symbol", 6);
	trie.insert("g_symbol", 7);
	trie.insert("h_symbol", 8);
	trie.insert("i_symbol", 9);
	trie.insert("j_symbol", 10);

	assert(trie.get("a_symbol")!! == 1);
	assert(trie.get("e_symbol")!! == 5);
	assert(trie.get("j_symbol")!! == 10);
	assert(!trie.contains("k_symbol"));

	trie.free();
	assert(!tracker.has_leaks());
}
