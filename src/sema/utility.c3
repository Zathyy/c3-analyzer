module analyzer::sema @if($feature(SEMA));

import analyzer::core;

<*
 @param [&in] node
*>
fn void SemaContext.error(&self, Node* node, String fmt, args...)
{
	diagnostics::diagnose(
		self.ws.allocator,
		self.section,
		node.offset.start,
		node.offset.end,
		ERROR,
		fmt,
		...args);
}

<*
 @param [&in] node
*>
fn void SemaContext.warn(&self, Node* node, String fmt, args...)
{
	diagnostics::diagnose(
		self.ws.allocator,
		self.section,
		node.offset.start,
		node.offset.end,
		WARN,
		fmt,
		...args);
}

<*
 @param [&in] node
*>
fn void SemaContext.info(&self, Node* node, String fmt, args...)
{
	diagnostics::diagnose(
		self.ws.allocator,
		self.section,
		node.offset.start,
		node.offset.end,
		INFO,
		fmt,
		...args);
}