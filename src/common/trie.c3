module parser::trie <Type>;

import std::math;
import std::collections::list;

const sz DENSE_CHILD_COUNT = 256;
const sz DENSE_CHILD_PROMOTION_THRESHOLD = 4;

struct Child @private
{
	char key;
	Node* node;
}

struct Node @private
{
	String label;
	bool has_value;
	Type value;
	List{Child} children;
	Node*[] dense_children;
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
		char first_byte = remaining[0];
		Node* child     = find_child(node, first_byte);

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
	Node* node = mem::alloc::new(self.alloc, Node, { .label = cloned_label });
	node.children.init(self.alloc, 0);
	return node;
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
		char first_byte = remaining[0];
		Node* child     = find_child(node, first_byte);
		if (!child)
		{
			set_child(node, first_byte, self.new_value_node(remaining, value));
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
		set_child(child, suffix[0], self.new_value_node(suffix, value));
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
	suffix.children = node.children;
	suffix.dense_children = node.dense_children;
	node.children = {};
	node.children.init(self.alloc, 0);
	node.dense_children = {};

	String old_label = node.label;
	node.label = old_label[..prefix_length - 1].copy(self.alloc);
	old_label.free(self.alloc);

	node.has_value = false;
	set_child(node, suffix.label[0], suffix);
}

// Helpers

fn Node* find_child(Node* node, char key) @private
{
	if (node.dense_children.len > 0) return node.dense_children[key];

	foreach (&child : node.children)
	{
		if (child.key == key) return child.node;
	}
	return null;
}

fn void set_child(Node* node, char key, Node* child_node) @private
{
	if (node.dense_children.len > 0)
	{
		node.dense_children[key] = child_node;
		return;
	}

	foreach (&child : node.children)
	{
		if (child.key == key)
		{
			child.node = child_node;
			return;
		}
	}

	node.children.push({ .key = key, .node = child_node });
	if (node.children.len() > DENSE_CHILD_PROMOTION_THRESHOLD) promote_children(node);
}

fn void promote_children(Node* node) @private
{
	Node*[] dense_children = alloc::alloc_array(node.children.allocator, Node*, DENSE_CHILD_COUNT);
	for (sz i = 0; i < DENSE_CHILD_COUNT; i++) dense_children[i] = null;

	foreach (child : node.children)
	{
		dense_children[child.key] = child.node;
	}

	node.children.free();
	node.dense_children = dense_children;
}

fn void free_node(Allocator alloc, Node* n) @private
{
	if (!n) return;

	if (n.dense_children.len > 0)
	{
		foreach (child : n.dense_children)
		{
			free_node(alloc, child);
		}
		alloc::free(alloc, n.dense_children);
	}
	else
	{
		foreach (child : n.children)
		{
			free_node(alloc, child.node);
		}
	}

	n.children.free();
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
