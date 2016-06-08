# lua-resty-model
an  easy-to-use sql mapper
# Quick start
See [quickstart.lua](https://github.com/pronan/lua-resty-model/blob/master/quickstart.lua "view source file").
The model api takes a table or a string parameter. If a table is given, you can enjoy chaining invocation:

    User:where{name='Tom'}:where{phone='123456'}

If a string is given, you have to write all conditions in one time:

    User:where"name='Tom' and phone='123456'"
But string is more flexible and powerful as it is directly passed to the WHERE clause.

# Todo
1. Foreign keys support
2. Auto create database table from Model if neccessary
3. Add `using` api in Model, RawQuery and QueryManager.
