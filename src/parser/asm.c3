module c3_parser::parser;

import c3_parser::ast;
import lexer;
import c3_parser::common;
import c3_parser::constants;

import std::collections::list;

fn Node? parse_asm_offset(Parser* p)
{
	uint start_pos = p.current_pos();
	Node offset = parse_expr(p)!;

	uint[*] data = views::@data{AsmOffsetViewFields}
	(
		EXPR, offset,
	);
	uint ex = p.ast.push_extra_block(&data);
	return p.ast.add_node(ASM_OFFSET, start_pos, start_pos, ex);
}

<*
	Asm [REG + BAR * 4], [&foo]
	asm_addr ::= '[' asm_expr
*>
fn Node? parse_asm_addr(Parser* p)
{   
    uint start_pos = p.current_pos();
    
    // [ expr ... ]
    Node base = parse_asm_expr(p)!;
    
    // Simple case: [foo]
    if (consume(p, RBRACKET)!)
    {
        return p.ast.add_node(ASM_ARG_MEMVAR, start_pos, p.current_pos(), (uint)base);
    }

    // Complex case: [base + index * scale + disp]
    Node index;
    uint scale = 1;
    Node disp;
	bool neg_index;

	if (p.is(PLUS) || p.is(MINUS))
    {
        neg_index = p.is(MINUS);
        p.advance()!;
    }

	if (p.is(INTEGER))
	{
		disp = parse_asm_offset(p)!;
	}
	else
	{
		index = parse_asm_expr(p)!;
        // Check for scale: [base + index * 4]
        if (consume(p, ASTERISK)!)
        {
            // We expect a literal for scale (1, 2, 4, 8)
            scale = (uint)p.current_text().to_uint() ?? 1;
            p.advance()!;
        }
        
        // Check for an additional displacement: [base + index * 4 + 16]
        if (p.is(PLUS) || p.is(MINUS))
        {
            p.advance()!;
            disp = parse_asm_offset(p)!;
        }
	}

    expect(p, RBRACKET)!;

    uint[*] data = views::@data{AsmArgAddrViewFields}
	(
		BASE, base,
		INDEX, index,
		SCALE, scale,
		DISP, disp,
	);
    uint ex = p.ast.push_extra_block(&data);
    return p.ast.add_node(ASM_ARG_ADDR, start_pos, p.current_pos(), ex);
}

// asm_reg ::= CT_IDENT | CT_CONST_IDENT
fn Node? parse_asm_reg(Parser* p)
{
    uint start_pos = p.current_pos();
    uint reg_id = p.pool.intern(p.current_text());
    p.advance()!;
    return p.ast.add_node(ASM_ARG_REG, start_pos, p.current_pos(), reg_id);
}

// asm_regvar ::= IDENT
fn Node? parse_asm_regvar(Parser* p)
{
    uint start_pos = p.current_pos();
    uint var_id = p.pool.intern(p.current_text());
    p.advance()!;
    // This represents a local variable used directly as a register
    return p.ast.add_node(ASM_ARG_REGVAR, start_pos, p.current_pos(), var_id);
}

// asm_addof ::= '&' IDENT
fn Node? parse_asm_addrof(Parser* p)
{
    uint start_pos = p.current_pos();
    expect(p, AMP)!;
    uint var_id = p.pool.intern(p.current_text());
    expect(p, IDENT)!;
    return p.ast.add_node(ASM_ARG_ADDROF, start_pos, p.current_pos(), var_id);
}

fn Node? parse_asm_argvalue(Parser* p)
{
    uint start_pos = p.current_pos();
    
    // nested expressions: ( 1 + 2 )
    if (consume(p, LPAREN)!)
    {
        Node expr = parse_expr(p)!;
        expect(p, RPAREN)!;
        return p.ast.add_node(ASM_ARG_EXPR, start_pos, p.current_pos(), (uint)expr);
    }

    // Immediates: 123, 0xFF, 3.14
    if (p.is(INTEGER) || p.is(FLOAT) || p.is(CONST_IDENT))
    {
        uint val_id = p.pool.intern(p.current_text());
        p.advance()!;
        return p.ast.add_node(ASM_ARG_IMM, start_pos, p.current_pos(), val_id);
    }

    p.error("Invalid assembly operand");
    return p.push_invalid_node(start_pos);
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
            return parse_asm_reg(p)!;
        case AMP:
            return parse_asm_addrof(p)!;
        case IDENT:
            return parse_asm_regvar(p)!;
		case MINUS:
		case INTEGER:
		case CONST_IDENT:
		case FLOAT:
		case LPAREN:
            return parse_asm_argvalue(p)!;
        default:
			p.error("Invalid asm operand");
			return p.push_invalid_node(start_pos);
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
            p.error("Expected asm instruction variant (e.g., width suffix) after '.'");
            return p.push_invalid_node(start_pos);
        }
        variant = p.pool.intern(p.current_text());
        p.advance()!;
    }

    uint args;
    @with_scratch(; watermark)
    {
        while (!consume(p, EOS)!)
        {
            Node arg = parse_asm_expr(p)!;
            scratch.push((uint)arg);
            
            if (consume(p, COMMA)!) 
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
        args = p.ast.push_extra_list(scratch_view(watermark, count));
    };

	uint[*] data = views::@data{AsmInstViewFields}
	(
		INSTRUCTION, instruction,
		VARIANT, variant,
		ARGS, args,
	);
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