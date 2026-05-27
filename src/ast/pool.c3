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

fn AstPool new(Allocator backing_allocator = mem)
{
	List{AstPoolMember} pool;
	pool.init_with_array(backing_allocator, { [0..INIT_POOL_SIZE-1] = { .ast = ast::new(backing_allocator), .free = true } });

	return { .allocator = backing_allocator, .pool = pool };
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

	AstPoolMember new_member = { .ast = ast::new(self.allocator), .free = false };
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
