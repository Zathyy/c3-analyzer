module parser::parser::error;

import lexer;

struct ParserError
{
	LogPriority level;
	Location loc;
	Token token;

	<*
	 The formatted error message
	*>
	String message;
}