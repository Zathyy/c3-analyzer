module analyzer::core::plog;

import std::collections::list;
import std::io;
import std::core::log;

macro void log(LogPriority priority, String fmt, ...)
{
	$if !$feature(PARSER_LIB):
		std::core::log::call_log(priority, std::core::log::default_category, fmt, ...$vaarg);
	$endif
}

macro void debug(String fmt, ...) => log(DEBUG, fmt, ...$vaarg);
macro void info(String fmt, ...) => log(INFO, fmt, ...$vaarg);
macro void error(String fmt, ...) => log(ERROR, fmt, ...$vaarg);
macro void warn(String fmt, ...) => log(WARN, fmt, ...$vaarg);
