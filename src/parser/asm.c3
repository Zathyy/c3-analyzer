module c3_parser::parser;

import c3_parser::ast;
import lexer;
import c3_parser::common;
import c3_parser::constants;

import std::collections::list;

fn Node? parse_asm_offset(ParseContext* ctx)
{
	uint start_pos = ctx.current_pos();
	Node offset = parse_expr(ctx)!;

	uint[*] data = views::@data{AsmOffsetViewFields}
	(
		EXPR, offset,
	);
	uint ex = ctx.ast.push_extra_block(&data);
	return ctx.ast.add_node(ASM_OFFSET, start_pos, start_pos, ex);
}

<*
	Asm [REG + BAR * 4], [&foo]
	asm_addr ::= '[' asm_expr
*>
fn Node? parse_asm_addr(ParseContext* ctx)
{   
    uint start_pos = ctx.current_pos();
    
    // [ expr ... ]
    Node base = parse_asm_expr(ctx)!;
    
    // Simple case: [foo]
    if (consume(ctx, RBRACKET)!)
    {
        return ctx.ast.add_node(ASM_ARG_MEMVAR, start_pos, ctx.current_pos(), (uint)base);
    }

    // Complex case: [base + index * scale + disp]
    Node index;
    uint scale = 1;
    Node disp;
	bool neg_index;

	if (ctx.is(PLUS) || ctx.is(MINUS))
    {
        neg_index = ctx.is(MINUS);
        ctx.advance()!;
    }

	if (ctx.is(INTEGER))
	{
		disp = parse_asm_offset(ctx)!;
	}
	else
	{
		index = parse_asm_expr(ctx)!;
        // Check for scale: [base + index * 4]
        if (consume(ctx, ASTERISK)!)
        {
            // We expect a literal for scale (1, 2, 4, 8)
            scale = (uint)ctx.current_text().to_uint() ?? 1;
            ctx.advance()!;
        }
        
        // Check for an additional displacement: [base + index * 4 + 16]
        if (ctx.is(PLUS) || ctx.is(MINUS))
        {
            ctx.advance()!;
            disp = parse_asm_offset(ctx)!;
        }
	}

    expect(ctx, RBRACKET)!;

    uint[*] data = views::@data{AsmArgAddrViewFields}
	(
		BASE, base,
		INDEX, index,
		SCALE, scale,
		DISP, disp,
	);
    uint ex = ctx.ast.push_extra_block(&data);
    return ctx.ast.add_node(ASM_ARG_ADDR, start_pos, ctx.current_pos(), ex);
}

// asm_reg ::= CT_IDENT | CT_CONST_IDENT
fn Node? parse_asm_reg(ParseContext* ctx)
{
    uint start_pos = ctx.current_pos();
    uint reg_id = ctx.pool.intern(ctx.current_text());
    ctx.advance()!;
    return ctx.ast.add_node(ASM_ARG_REG, start_pos, ctx.current_pos(), reg_id);
}

// asm_regvar ::= IDENT
fn Node? parse_asm_regvar(ParseContext* ctx)
{
    uint start_pos = ctx.current_pos();
    uint var_id = ctx.pool.intern(ctx.current_text());
    ctx.advance()!;
    // This represents a local variable used directly as a register
    return ctx.ast.add_node(ASM_ARG_REGVAR, start_pos, ctx.current_pos(), var_id);
}

// asm_addof ::= '&' IDENT
fn Node? parse_asm_addrof(ParseContext* ctx)
{
    uint start_pos = ctx.current_pos();
    expect(ctx, AMP)!;
    uint var_id = ctx.pool.intern(ctx.current_text());
    expect(ctx, IDENT)!;
    return ctx.ast.add_node(ASM_ARG_ADDROF, start_pos, ctx.current_pos(), var_id);
}

fn Node? parse_asm_argvalue(ParseContext* ctx)
{
    uint start_pos = ctx.current_pos();
    
    // nested expressions: ( 1 + 2 )
    if (consume(ctx, LPAREN)!)
    {
        Node expr = parse_expr(ctx)!;
        expect(ctx, RPAREN)!;
        return ctx.ast.add_node(ASM_ARG_EXPR, start_pos, ctx.current_pos(), (uint)expr);
    }

    // Immediates: 123, 0xFF, 3.14
    if (ctx.is(INTEGER) || ctx.is(FLOAT) || ctx.is(CONST_IDENT))
    {
        uint val_id = ctx.pool.intern(ctx.current_text());
        ctx.advance()!;
        return ctx.ast.add_node(ASM_ARG_IMM, start_pos, ctx.current_pos(), val_id);
    }

    ctx.error("Invalid assembly operand");
    return ctx.push_invalid_node(start_pos);
}

<*
	asm_expr ::= asm_addr | asm_reg | asm_regvar | asm_addrof | asm_argvalue
	asm_reg = CT_IDENT | CT_CONST_IDENT (register name)
	asm_regvar = IDENT (variable)
	asm_addof = '&' IDENT (variable address)
	asm_argvalue = ('-'? INTEGER) | CONST_IDENT | FLOAT | '(' expr ')'
*>
fn Node? parse_asm_expr(ParseContext* ctx)
{
    uint start_pos = ctx.current_pos();
    switch (ctx.current().kind)
    {
        case LBRACKET:
            ctx.advance()!;
            return parse_asm_addr(ctx)!;
        case CT_IDENT:
        case CT_CONST_IDENT:
            return parse_asm_reg(ctx)!;
        case AMP:
            return parse_asm_addrof(ctx)!;
        case IDENT:
            return parse_asm_regvar(ctx)!;
		case MINUS:
		case INTEGER:
		case CONST_IDENT:
		case FLOAT:
		case LPAREN:
            return parse_asm_argvalue(ctx)!;
        default:
			ctx.error("Invalid asm operand");
			return ctx.push_invalid_node(start_pos);
    }
}

<*
	asm_label | asm_stmt
	asm_label     ::= CONST_IDENT ':'
	asm_stmt      ::= IDENT | int ('.' IDENT) )? asm_expr_list? ';'
	asm_expr_list ::= asm_expr (',' asm_expr)* ','?
*>
fn Node? parse_asm_stmt(ParseContext* ctx)
{
    uint start_pos = ctx.current_pos();

    // Handle ASM_LABEL: CONST_IDENT ':'
    if (ctx.is(CONST_IDENT))
    {
        uint label_name = ctx.pool.intern(ctx.current_text());
        ctx.advance()!; // consume CONST_IDENT
        expect(ctx, COLON)!;
        
        return ctx.ast.add_node(ASM_LABEL, start_pos, ctx.current_pos(), label_name);
    }

    if (!ctx.is(IDENT) && !ctx.is(INT))
    {
        ctx.error("Expected an asm instruction (mnemonic) or a label.");
        return ctx.push_invalid_node(start_pos);
    }

    uint instruction = ctx.pool.intern(ctx.current_text());
    ctx.advance()!;

    uint variant;
    if (consume(ctx, DOT)!)
    {
        if (!ctx.is(IDENT))
        {
            ctx.error("Expected asm instruction variant (e.g., width suffix) after '.'");
            return ctx.push_invalid_node(start_pos);
        }
        variant = ctx.pool.intern(ctx.current_text());
        ctx.advance()!;
    }

    uint args;
    @with_scratch(; watermark)
    {
        while (!consume(ctx, EOS)!)
        {
            Node arg = parse_asm_expr(ctx)!;
            scratch.push((uint)arg);
            
            if (consume(ctx, COMMA)!) 
            {
                continue; 
            }
            
            if (!ctx.is(EOS))
            {
                ctx.error("Expected ';' or ',' in assembly operand list.");
                break;
            }
        }
        uint count = (uint)scratch.len() - watermark;
        args = ctx.ast.push_extra_list(scratch_view(watermark, count));
    };

	uint[*] data = views::@data{AsmInstViewFields}
	(
		INSTRUCTION, instruction,
		VARIANT, variant,
		ARGS, args,
	);
    uint ex = ctx.ast.push_extra_block(&data);
    return ctx.ast.add_node(ASM_INST, start_pos, ctx.current_pos(), ex);
}


<*
	asm ::= 'asm' @pure? '{' asm_stmt* '}' | 'asm' '(' string ')'
*>
fn Node? parse_asm_block_stmt(ParseContext* ctx)
{
	uint start_pos = ctx.current_pos();
	expect(ctx, ASM)!;
	AsmFlags flags;
	Node block;
	Node asm_string_expr;
	
	if (ctx.is(AT_IDENT))
	{
		String lexeme = ctx.current_text();
		if (lexeme == constants::KW_AT_PURE)
		{
			flags.is_volatile = false;
		}
		else
		{
			ctx.error("Only the '@pure' attribute is allowed");
			ctx.skip_until({ EOF, EOS, RBRACE })!;
			return ctx.push_invalid_node(start_pos);
		}
		expect(ctx, AT_IDENT)!;
	}
	if (consume(ctx, LBRACE)!)
	{
		@with_scratch(; watermark)
		{
			uint block_start_pos = ctx.current_pos();
			while (!ctx.is(RBRACE) && !ctx.eof())
			{
				Node stmt = parse_asm_stmt(ctx)!;
				scratch.push((uint)stmt);
			}
			expect(ctx, RBRACE)!;
			uint count = (uint)scratch.len() - watermark;
			uint ex = ctx.ast.push_extra_list(scratch_view(watermark, count));
			block = ctx.ast.add_node(ASM_STMT_LIST, block_start_pos, ctx.current_pos(), ex);
		};
	}
	else if (consume(ctx, LPAREN)!)
	{
		flags.is_string_style = true;
		asm_string_expr = parse_expr(ctx)!;
		expect(ctx, RPAREN)!;

		if (ctx.is(AT_IDENT))
		{
			String lexeme = ctx.current_text();
			if (lexeme == constants::KW_AT_PURE)
			{
				flags.is_volatile = false;
			}
			else
			{
				ctx.error("Only the '@pure' attribute is allowed.");
			}
			expect(ctx, AT_IDENT)!;
		}
		expect(ctx, EOS)!;
	}
	else
	{
		ctx.error("Expected '{' or '(' after 'asm'");
		return ctx.push_invalid_node(start_pos);
	}

	uint[*] data = views::@data{AsmViewFields}
	(
		FLAGS, flags,
		STRING_EXPR, asm_string_expr,
		BLOCK, block,
	);
    
	uint ex = ctx.ast.push_extra_block(&data);
    return ctx.ast.add_node(ASM_BLOCK_STMT, start_pos, ctx.current_pos(), ex);
} 