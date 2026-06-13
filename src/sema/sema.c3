module parser::sema;

import parser::ast;

import parser::workspace @norecurse;
import parser::diagnostics;

struct SemaContext 
{
	ModuleSection* section;
	Workspace* ws;
}

<*
 @param [&in] node
*>
fn void SemaContext.error(&self, Node* node, String fmt, args...)
{
	diagnostics::diagnose(
		self.ws.allocator,
		self.section,
		node.start_token,
		node.end_token,
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
		node.start_token,
		node.end_token,
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
		node.start_token,
		node.end_token,
		INFO,
		fmt,
		...args);
}