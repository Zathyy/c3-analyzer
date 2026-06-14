module analyzer::core;

<*
	Zero-cost Option type
*>
typedef Option<Type> = Type*;

fn Type*? Option.get(&self)
{
	if (self == null)
	{
		return NOT_FOUND~;
	}

	return (Type*) self;
}

fn void Option.set(&self, Type* val)
{
	*self = (Option{Type}) val;
}

alias OptionLit<Type, NULL_VALUE> = Type;

fn Type? OptionLit.get(&self)
{
	if (*self == NULL_VALUE)
	{
		return NOT_FOUND~;
	}

	return *self;
}
