module c3_parser::common;

typedef FileID = ushort;

struct SourceSpan 
{
	usz start;
	usz end;
	FileID file_id;
}

// TODO: what is valid state?
// since start might be 0
fn bool SourceSpan.is_valid(self) @inline 
{
	return self.start != 0 && self.end != 0;
}

fn SourceSpan SourceSpan.combine(self, SourceSpan b) 
{
	return { .start = self.start, .end = b.end, .file_id = self.file_id };
}

struct Position 
{
	usz line;
	usz column;
}

//TODO: what name? Path clashes with std::io::path
// so i went with CPath - CommonPath
struct CPath
{
	SourceSpan span;
	String name;
}