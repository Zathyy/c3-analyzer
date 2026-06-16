module std::collections::nullable <Type>;
import std::io;

typedef Nullable = Type*;

const Nullable EMPTY = {};

fn sz? Nullable.to_format(Nullable* self, Formatter* f) @dynamic
{
	sz? size;
	
	if (*self)
	{
		size += f.printf("%s", *((Type*)self));
	}
	else
	{
		size += f.print("null");
	}
	
	return size;
}

fn Type*? Nullable.get(self) @inline => self ? (Type*)self : NOT_FOUND~;

fn void Nullable.set(&self, Type* val) @inline => *self = (Nullable)val;

fn void Nullable.reset(&self) @inline => *self = (Nullable)null;

fn Nullable value(Type* val) @inline => (Nullable)val;