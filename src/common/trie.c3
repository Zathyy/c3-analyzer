module parser::trie <Type>;

import std::math;

const sz SIZE = char::max;

struct Node @private
{
	String label;
	bool has_value;
	Type value;
	Node*[SIZE] children;
}

struct CompressedTrie
{
	Allocator alloc;
	Node* root;
}

fn void CompressedTrie.init(&self, Allocator alloc)
{
	self.alloc = alloc;
	self.root = self.new_node("");
}

fn void CompressedTrie.free(&self)
{
	free_node(self.alloc, self.root);
	*self = { };
}

fn Node*? CompressedTrie.find_node(&self, String key)
{
	Node* node       = self.root;
	String remaining = key;

	while (remaining.len > 0)
	{
		sz first_byte = remaining[0];
		Node* child   = node.children[first_byte];

		if (!child) return NOT_FOUND~;

		sz prefix_length = common_prefix_length(remaining, child.label);
		if (prefix_length != child.label.len) return NOT_FOUND~;

		node = child;
		remaining = remaining[prefix_length..];
	}

	if (!node.has_value) return NOT_FOUND~;

	return node;
}

fn Type? CompressedTrie.get(self, String key)
{
	Node* child = self.find_node(key)!;
	return child.value;
}

fn Type*? CompressedTrie.get_ref(&self, String key)
{
	Node* child = self.find_node(key)!;
	return &child.value;
}

fn Node* CompressedTrie.new_node(&self, String label)
{
	String cloned_label = label.copy(self.alloc);
	return mem::alloc::new(self.alloc, Node, { .label = cloned_label });
}

fn Node* CompressedTrie.new_value_node(&self, String label, Type value = { })
{
	Node* node = self.new_node(label);
	node.has_value = true;
	node.value = value;
	return node;
}

fn void CompressedTrie.insert(&self, String key, Type value)
{
	Node* node       = self.root;
	String remaining = key;

	while (remaining.len > 0)
	{
		sz first_byte = remaining[0];
		Node* child   = node.children[first_byte];
		if (!child)
		{
			node.children[first_byte] = self.new_value_node(remaining, value);
			return;
		}

		sz prefix_length = common_prefix_length(remaining, child.label);

		if (prefix_length == child.label.len)
		{
			node = child;
			remaining = remaining[prefix_length..];
			continue;
		}

		self.split_child(child, prefix_length);

		if (prefix_length == remaining.len)
		{
			child.has_value = true;
			child.value = value;
			return;
		}

		String suffix = remaining[prefix_length..];
		child.children[suffix[0]] = self.new_value_node(suffix, value);
		return;
	}

	node.has_value = true;
	node.value = value;
}

fn bool CompressedTrie.contains(self, String key)
{
	return @ok(self.find_node(key));
}

fn void CompressedTrie.split_child(&self, Node* node, sz prefix_length)
{
	Node* suffix = self.new_node(node.label[prefix_length..]);

	suffix.has_value = node.has_value;
	suffix.value = node.value;
	for (sz i = 0; i < SIZE; i++)
	{
		suffix.children[i] = node.children[i];
		node.children[i] = null;
	}

	String old_label = node.label;
	node.label = old_label[..prefix_length - 1].copy(self.alloc);
	old_label.free(self.alloc);

	node.has_value = false;
	node.children[suffix.label[0]] = suffix;
}

// Helpers

fn void free_node(Allocator alloc, Node* n) @private
{
	if (!n) return;

	foreach (node : n.children)
	{
		free_node(alloc, node);
	}

	n.label.free(alloc);
	mem::alloc::free(alloc, n);
}

fn sz common_prefix_length(String s1, String s2)
{
	sz min_length = math::min(s1.len, s2.len);
	if (min_length == 0) return 0;

	sz length = 0;
	for (sz i = 0; i < min_length; i++)
	{
		if (s1[i] != s2[i]) break;
		length++;
	}

	return length;
}
