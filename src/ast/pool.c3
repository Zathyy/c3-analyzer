module parser::ast::pool;

import std::collections::list;

const int INIT_POOL_SIZE = 10;

struct AstPool
{
	Allocator allocator;
	List{AstPoolMember} pool;
}

struct AstPoolMember
{
	Ast ast;
	bool free;
}

fn void AstPool.init(&self, Allocator backing_allocator = mem)
{
	self.allocator = backing_allocator;
	self.pool.init(backing_allocator);
	for (int i = 0; i < INIT_POOL_SIZE; i++)
	{
		self.pool.push({ .free = true });
	}

	foreach (member : self.pool)
	{
		member.ast.init(backing_allocator);
	}
}

fn Ast* AstPool.obtain(&self)
{
	foreach (&member : self.pool)
	{
		if (member.free)
		{
			member.free = false;
			return &member.ast;
		}
	}

	AstPoolMember new_member = { .free = false };
	new_member.ast.init(self.allocator);
	self.pool.push(new_member);
	return &self.pool[^1].ast;
}

fn void? AstPool.release(&self, Ast* ast)
{
	foreach (&member : self.pool)
	{
		if (&member.ast == ast)
		{
			member.ast.clear();
			member.free = true;
			return;
		}
	}

	return NOT_FOUND~;
}

fn void AstPool.free(&self)
{
	foreach(member : self.pool)
	{
		member.ast.free();
	}

	self.pool.free();
}
