module c3_parser::parser::error;

import lexer;
import c3_parser::common;


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
