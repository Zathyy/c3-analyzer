module parser::ast::serialize @if($feature(PARSER_CLI));

import parser::ast;
import std::collections::maybe;

alias fmt = string::format;
alias tfmt = string::tformat;

fn void push_indent(JsonOutput* output, int indent, int depth)
{
	if (indent != -1) output.append_char_repeat(' ', (sz) (indent * depth));
}
fn void push_newline(JsonOutput* output, int indent, String or = "")
{
	if (indent != -1) 
	{
		output.append_char('\n');
	}
	else if (lengthof(or) > 0)
	{
		output.append(or);
	}
}

macro void serialize(JsonOutput* output, item, StringPool spool, int indent, int depth) @local {
	$switch:
		$case $Typeof(item) == Node*:
			node_serialize(item, output, spool, indent, depth);

		$case $defined(Option{Node} x = item):
			node_serialize((Node*) item, output, spool, indent, depth);

		// $case $Typeof(item) == TypeExpr:

		$case $Typeof(item)::kind == BITSTRUCT:
			output.start_obj(indent);
			$foreach $m : $Typeof(item)::members:
				$if $Typeof(item.$m) == bool:
					if (item.$m) output.ser_entry($m.name, item.$m, spool, indent, depth + 1);
				$else
					output.ser_entry($m.name, item.$m, spool, indent, depth + 1);
				$endif
			$endforeach
			if (output.char_at(output.len() - 2) != ',')
			{
				output.chop(output.len() - 1);
				output.append('}');
			}
			else
			{
				output.end_obj(indent, depth);
			}

		$case $Typeof(item)::kind == STRUCT:
			output.start_obj(indent);
			$foreach $m : $Typeof(item)::members:
				output.ser_entry($m.name, item.$m, spool, indent, depth + 1);
			$endforeach
			output.end_obj(indent, depth);

		$case $Typeof(item) == StringID:
			output.appendf(`"%s" /* id: %d */`, spool.get(item)!!, item);

		$case $defined(item[0]) &&& $defined(lengthof(item)):
			sz l_len = lengthof(item);
      if (l_len == 0)
			{
				output.append("[]");
				return;
			}
      output.append("[");
      push_newline(output, indent);

      foreach (i, el : item) {
				push_indent(output, indent, depth + 1);
        serialize(output, el, spool, indent, depth + 1);
        if (i < l_len - 1) output.append_char(',');
        push_newline(output, indent, or: " ");
      }
			push_indent(output, indent, depth);
      output.append("]");

		$case $defined(item.get()) &&& $defined(item.get()!) &&& $defined(Maybe{$Typeof(item.get()!!)} x = item):
			if (try v = item.get())
			{
				serialize(output, v, spool, indent, depth);
			}
			else
			{
				output.append("null");
			}

		$default:
			output.appendf(`"%s"`, item);

	$endswitch
}

alias JsonOutput @local = DString;

macro void JsonOutput.ser_entry(&self, String key, item, StringPool spool, int indent, int depth)
{
	push_indent(self, indent, depth);
	self.appendf("\"%s\": ", key.treplace("\"", "\\\""));
	serialize(self, item, spool, indent, depth);
	self.append(",");
	push_newline(self, indent, or: " ");
}

fn void JsonOutput.start_obj(&self, int indent)
{
	self.append_char('{');
	push_newline(self, indent);
}
fn void JsonOutput.end_obj(&self, int indent, int depth)
{
	self.chop(self.len() - 2);
	push_newline(self, indent, or: " ");
	push_indent(self, indent, depth);
	self.append_char('}');
}

fn void node_serialize(Node* self, JsonOutput* output, StringPool spool, int indent, int depth) @local
{
	if (self == null)
	{
		output.append("null");
		return;
	}

	output.start_obj(indent);
	output.ser_entry("kind", self.kind, spool, indent, depth + 1);
	output.ser_entry("visibility", self.visibility, spool, indent, depth + 1);
	output.ser_entry("flags", self.flags, spool, indent, depth + 1);

	var $sw = "switch (self.kind) {";
	$foreach $m : Node::members[^1].members:
		$sw +++= @sprintf(`case %s: output.ser_entry("%s", self.$eval("%s"), spool, indent, depth + 1);`, @str_upper($m.name), $m.name, $m.name);
	$endforeach
	$sw +++= "default: }";
	$expand($sw);

	output.end_obj(indent, depth);
}

<* 
	@param indent : "if its value is -1, the output won't be prettified (all on one line). Else, it will be the indent size"
*>
fn String Node.serialize(&self, StringPool spool, Allocator allocator = tmem, int indent = -1)
{
	JsonOutput output;
	output.init(allocator);

	node_serialize(self, &output, spool, indent, 0);
	return output.str_view();
}

