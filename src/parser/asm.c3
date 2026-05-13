module c3_parser::parser;

import c3_parser::ast;
import lexer;
import c3_parser::common;
import c3_parser::constants;

import std::collections::list;

<*
	Asm [REG + BAR * 4], [&foo]
	asm_addr ::= '[' asm_expr
*>
fn Node? parse_asm_addr(Parser* p)
{	
	
}	

<*
	asm_expr ::= asm_addr | asm_reg | asm_regvar | asm_addrof | asm_argvalue
	asm_reg = CT_IDENT | CT_CONST_IDENT (register name)
	asm_regvar = IDENT (variable)
	asm_addof = '&' IDENT (variable address)
	asm_argvalue = ('-'? INTEGER) | CONST_IDENT | FLOAT | '(' expr ')'
*>
fn Node? parse_asm_expr(Parser* p)
{
	uint start_pos = p.current_pos();
	switch (p.current().kind)
	{
		case LBRACKET:
			p.advance()!;
			return parse_asm_addr(p)!;
		case CT_IDENT:
		case CT_CONST_IDENT:

		
	}
}

<*
	asm_label | asm_stmt
	asm_label     ::= CONST_IDENT ':'
	asm_stmt      ::= IDENT | int ('.' IDENT) )? asm_expr_list? ';'
	asm_expr_list ::= asm_expr (',' asm_expr)* ','?
*>
fn Node? parse_asm_stmt(Parser* p)
{
    uint start_pos = p.current_pos();

    // Handle ASM_LABEL: CONST_IDENT ':'
    if (p.is(CONST_IDENT))
    {
        uint label_name = p.pool.intern(p.current_text());
        p.advance()!; // consume CONST_IDENT
        expect(p, COLON)!;
        
        return p.ast.add_node(ASM_LABEL, start_pos, p.current_pos(), label_name);
    }

    if (!p.is(IDENT) && !p.is(INT))
    {
        p.error("Expected an asm instruction (mnemonic) or a label.");
        return p.push_invalid_node(start_pos);
    }

    uint instruction = p.pool.intern(p.current_text());
    p.advance()!;

    uint variant;
    if (consume(p, DOT)!)
    {
        if (!p.is(IDENT))
        {
            p.error("Expected asm instruction variant (e.g., width suffix) after '.'.");
            return p.push_invalid_node(start_pos);
        }
        variant = p.pool.intern(p.current_text());
        p.advance()!;
    }

    uint args_list_ex;
    @with_scratch(; watermark)
    {
        while (!consume(p, EOS)!)
        {
            Node arg = parse_asm_expr(p)!;
            scratch.push((uint)arg);
            
            if (p.consume(COMMA)!) 
            {
                continue; 
            }
            
            if (!p.is(EOS))
            {
                p.error("Expected ';' or ',' in assembly operand list.");
                break;
            }
        }
        uint count = (uint)scratch.len() - watermark;
        args_list_ex = p.ast.push_extra_list(scratch_view(watermark, count));
    };

    uint[3] data = { instruction, variant, args_list_ex };
    uint ex = p.ast.push_extra_block(&data);
    
    return p.ast.add_node(ASM_INST, start_pos, p.current_pos(), ex);
}


<*
	asm ::= 'asm' @pure? '{' asm_stmt* '}' | 'asm' '(' string ')'
*>
fn Node? parse_asm_block_stmt(Parser* p)
{
	uint start_pos = p.current_pos();
	expect(p, ASM)!;
	AsmFlags flags;
	Node block;
	Node asm_string_expr;
	
	if (p.is(AT_IDENT))
	{
		String lexeme = p.current_text();
		if (lexeme == constants::KW_AT_PURE)
		{
			flags.is_volatile = false;
		}
		else
		{
			p.error("Only the '@pure' attribute is allowed");
			p.skip_until({ EOF, EOS, RBRACE })!;
			return p.push_invalid_node(start_pos);
		}
		expect(p, AT_IDENT)!;
	}
	if (consume(p, LBRACE)!)
	{
		@with_scratch(; watermark)
		{
			uint block_start_pos = p.current_pos();
			while (!p.is(RBRACE) && !p.eof())
			{
				Node stmt = parse_asm_stmt(p)!;
				scratch.push((uint)stmt);
			}
			expect(p, RBRACE)!;
			uint count = (uint)scratch.len() - watermark;
			uint ex = p.ast.push_extra_list(scratch_view(watermark, count));
			block = p.ast.add_node(ASM_STMT_LIST, block_start_pos, p.current_pos(), ex);
		};
	}
	else if (consume(p, LPAREN)!)
	{
		flags.is_string_style = true;
		asm_string_expr = parse_expr(p)!;
		expect(p, RPAREN)!;

		if (p.is(AT_IDENT))
		{
			String lexeme = p.current_text();
			if (lexeme == constants::KW_AT_PURE)
			{
				flags.is_volatile = false;
			}
			else
			{
				p.error("Only the '@pure' attribute is allowed.");
			}
			expect(p, AT_IDENT)!;
		}
		expect(p, EOS)!;
	}
	else
	{
		p.error("Expected '{' or '(' after 'asm'");
		return p.push_invalid_node(start_pos);
	}

	uint[*] data = views::@data{AsmViewFields}
	(
		FLAGS, flags,
		STRING_EXPR, asm_string_expr,
		BLOCK, block,
	);
    
	uint ex = p.ast.push_extra_block(&data);
    return p.ast.add_node(ASM_BLOCK_STMT, start_pos, p.current_pos(), ex);
} 