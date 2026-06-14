module analyzer::analyzer::error;
import analyzer::core::lexer;

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
