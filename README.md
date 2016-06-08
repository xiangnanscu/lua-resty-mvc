# lua-resty-model
an  easy-to-use sql mapper
# Quick start
The model api takes a table or a string. If a table is given, you can enjoin invocation chaining:

    User:where{name='Tom'}:where{phone='123456'}

If a string is given, you have to write all conditions in one time:

    User:where"name='Tom' and phone='123456'"
But string is more flexible and powerful.

See [quickstart.lua](https://github.com/pronan/lua-resty-model/blob/master/quickstart.lua "view source file").

# Todo
1. Foreign keys support
2. Auto create database table from Model if neccessary
3. Add `using` api in Model, RawQuery and QueryManager.
