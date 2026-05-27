module parser::parser::error;

import lexer;
import parser::common;


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
