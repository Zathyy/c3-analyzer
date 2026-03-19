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
| **typedef** | 🟡 | very basic right now
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
| **defer** | ❌ |
| **Decleration/DeclStmt** | ✅ | aka local variable
| **Expression/ExprStmt** | ✅ | 

## Expressions

Expressions uses pratt parsing with binding power 

| Feature | Status | Notes |
| :--- | :---: | :--- |
| **literal** | ✅ | integer, real, string, bool
| **type** | ✅ | integer, real, string
| **binary** | ✅ | eg. 5 * 10
| **unary** | ✅ | eg. 5 * 10
| **ternary** | ✅ | 
| **call** | ✅ | eg. foo()
| **builtin** | ❌ |


