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

| Feature | Status | Notes |
| :--- | :---: | :--- |
| **module** | 🟡 | attributes, generics are not implemented
| **import** | ✅ | 
| **alias** | 🟡 | 
| **typedef** | 🟡 | supports typedef MyType = 'Type'
| **function** | ✅ | except for functions using ´=>´
| **macro** | ❌ | 
| **struct** | ❌ | 
| **enum** | ❌ | 
| **constdef** | ❌ | 
| **contract** | ❌ | 
| **globals** | ✅ | global variables


## Statements

| Feature | Status | Notes |
| :--- | :---: | :--- |
| **compound** | ✅ |
| **return** | ✅ |
| **defer** | ✅ |
| **Decleration/DeclStmt** | ✅ | aka local variable
| **Expression/ExprStmt** | ✅ | 

## Expressions

Expressions uses pratt parsing with binding power 

| Feature | Status | Notes |
| :--- | :---: | :--- |
| **literal** | ✅ | integer, real, string, bool
| **type** | ✅ | type inside an Expr
| **binary** | ✅ | eg. 5 * 10
| **unary** | ✅ | eg. 5 * 10
| **ternary** | ✅ | 
| **call** | ✅ | eg. foo()
| **builtin** | ❌ |
| **cast** | ❌ |
| **catch** | ❌ |
| **swizzle** | ❌ |
