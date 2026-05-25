module buffered_log;

import std::collections::list;
import std::io;

struct Message
{
	LogPriority priority;
	String message;
}

List{Message} messages;

macro void log(
	LogPriority priority,
	String fmt, 
	...)
{
	String msg = string::format(mem, fmt, ...$vaarg);
	messages.push({ priority, msg });
}

fn void init()
{
	messages.init(mem);
}

fn void flush()
{
	foreach (msg : messages)
	{
		mem::free(msg.message);
	}

	messages.clear();
}