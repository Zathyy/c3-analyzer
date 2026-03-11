module c3_parser::common;

typedef FileID = ushort;

struct SourceSpan 
{
	usz start;
	usz end;
	FileID file_id;
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
struct CPath
{
	SourceSpan span;
	String name;
}