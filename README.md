# C3 Parser

<p>
Checkout the main file for example
</p>

---

<p>
Most of the api should be stable but its still in early developement
</p>

# TODOS
- Cleanup utils/ast.c3, its getting pretty messy
- More tests, there should be tests for every situation the parser might be put to!.
- Implement more features
- More/Better error handling?
- Custom Lexer or rewrite the current to be more memory efficient?

# Feature support chart

<p>
Types should be working aswell as generics
</p>

## Declerations

<p>
Declerations aka Top level statements
</p>

<p>
✅ = Fully implemented (should be) <br>
🟡 = Partially implmented <br>
❌ = Not yet implemented <br>
</p>

| Feature | Status | Notes |
| :--- | :---: | :--- |
| **module** | 🟡 | attributes, generics are not implemented
| **import** | 🟡 | mostly working, missing multi decleration, attributes? (@public)
| **alias** | 🟡 | 
| **typedef** | 🟡 | supports typedef MyType = 'Type'
| **function** | 🟡 | except for functions using ´=>´
| **macro** | ❌ | 
| **struct** | ❌ | 
| **enum** | ❌ | 
| **constdef** | ❌ | 
| **contract** | ❌ | 
| **globals** | 🟡 | global variables, missing attributes

## Statements

| Feature | Status | Notes |
| :--- | :---: | :--- |
| **compound** | ✅ |
| **return** | ✅ |
| **defer** | ✅ |
| **while** | ❌ |
| **foreach** | ❌ |
| **for** | ❌ |
| **if** | 🟡 | if, else, else if. Supports only one expression right now
| **Decleration/DeclStmt** | ✅ | local variable within a statement
| **Expression/ExprStmt** | 🟡 | support depends on parse_expr. expr in a statement

## Expressions

Expressions uses pratt parsing with binding power 

| Feature | Status | Notes |
| :--- | :---: | :--- |
| **literal** | ✅ | integer, real, string, bool
| **type** | ✅ | type inside an Expr
| **binary** | ✅ | eg. 5 * 10
| **unary** | ✅ | eg. -5
| **ternary** | ✅ | eg. value > x ? : y
| **call** | ✅ | eg. foo()
| **builtin** | ❌ |
| **cast** | 🟡 | should work, but not fully tested eg. (void*)my_var
| **try** | ❌ |
| **catch** | ❌ |
| **swizzle** | ❌ |
