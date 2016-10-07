local encode = require"cjson".encode
local Model = require"resty.mvc.model"
local Field = require"resty.mvc.modelfield"
local Q = require"resty.mvc.q"
local Migrate = require"resty.mvc.migrate"

local Moreinfo = Model:class{table_name = "moreinfo", 
    fields = {
        weight = Field.FloatField{min=0},
        height = Field.FloatField{min=0}, 
    }
}

local Detail = Model:class{
    table_name = "detail", 
    fields = {
        sex = Field.CharField{maxlen=1},
        age = Field.IntegerField{min=1},
        info = Field.ForeignKey{Moreinfo}
    }
}

local User = Model:class{
    table_name = "user", 
    fields = {
        name = Field.CharField{maxlen=50},
        money = Field.FloatField{}, 
        detail = Field.ForeignKey{Detail}
    }
}

local Product = Model:class{
    table_name = "product", 
    fields = {
        name = Field.CharField{maxlen=50},
        price = Field.FloatField{min=0}, 
    }
}

local Record = Model:class{
    table_name = "record", 
    fields = {
        buyer = Field.ForeignKey{User},
        seller = Field.ForeignKey{User},
        product = Field.ForeignKey{Product},
        count = Field.IntegerField{min=1}, 
        time = Field.DateTimeField{auto_add=true}, 
    }
}

local models = {Record, Product, User, Detail, Moreinfo}
Migrate(models, false)

local function eval(s)
    local f = loadstring('return '..s)
    setfenv(f, {User=User, Product=Product, Record=Record, Detail=Detail, Moreinfo=Moreinfo, Q=Q})
    return f()
end
local function simple_sql_formatter(s, indent)
    indent = indent or '    '
    -- just add new line after key words
    for i, v in ipairs({'SELECT', 'FROM', 'INNER JOIN', 'WHERE'}) do
        s = s:gsub(v, function(v) return '\n'..indent..v end)
    end
    return s
end
local function render_to_browser(e)
    local stm = simple_sql_formatter(eval(e):to_sql())
    ngx.print(string.format([[%s  
    %s


]], e, stm))
end

ngx.header.content_type = "text/plain; charset=utf-8"

--User:instance({name='Kate', age='20', money='1000'})
local statement_string = [[
User:where()
User:where{}
User:where{id=1}
User:where{id__gt=2}
User:where{id__in={1, 2, 3}}
User:where{name='kate'}
User:where{name__endswith='e'}
User:where{name__contains='a'}
User:where{id=1, name='kate'}
User:where{id=1}:where{name='kate'}
User:where{id__lt=3, name__startswith='k'}

User:where{Q{id__gt=2}}
User:where{Q{id__gt=2}, Q{id__lt=5}}
User:where{Q{id__gt=2, id__lt=5}}
User:where{Q{id__gt=2, id__lt=5}}:where{Q{name__startswith='k'}}
User:where{Q{id__gt=2, id__lt=5}}:where{name__startswith='k'}
User:where{Q{id__gt=2}/Q{id__lt=5}*Q{name__startswith='k'}}
User:where{Q{id__gt=2}/Q{id__lt=5}, name__startswith='k'}


Record:where{buyer=1}
Record:where{buyer__gt=1}
Record:where{buyer__in={1, 2}}
Record:where{buyer__name='kate'}
Record:where{buyer__name__startswith='k'}
Record:where{Q{buyer__name__startswith='k'}/Q{buyer__money__gt=100.2}}
Record:where{Q{buyer__name__startswith='k'}/Q{seller__money__gt=100.2}/Q{product__price__lt=50}}

Record:where{buyer=1}:join{'buyer'}
Record:where{buyer=1}:join{'seller'}
Record:where{buyer=1}:join{'buyer', 'seller'}
Record:where{buyer=1}:join{'buyer', 'seller', 'product'}

Record:where{seller__detail=1}
Record:where{seller__detail__lt=1}
Record:where{seller__detail__in={1, 2, 3}}
Record:where{seller__detail__sex='w'}
Record:where{seller__detail__age=20}
Record:where{seller__detail__age__gt=20}
Record:where{seller__detail__info=2}
Record:where{seller__detail__info__lt=2}
Record:where{seller__detail__info__in={1, 2}}
Record:where{seller__detail__info__weight=55}
Record:where{seller__detail__info__weight__gt=55}
Record:where{seller__detail__info__weight__in={45, 55}}

Record:where{Q{buyer__detail__age__gt=20}/Q{seller__detail__age__gt=20}}
Record:where{Q{buyer__detail__info__weight__gt=20}/Q{seller__detail__info__height__gt=20}}
Record:where{Q{seller__detail__info__weight__gt=20}/Q{buyer__detail__info__height__gt=20}, buyer__detail__info__height__lt=120}:join{'buyer'}
Record:where{Q{seller__detail__info__weight__gt=20}/Q{buyer__detail__info__height__gt=20}, buyer__detail__info__height__lt=120}:join{'buyer', 'seller', 'product'}
]]

local statement_string2 = [[

Record:where{buyer__detail__info__weight__gt=55}
Record:where{Q{buyer__detail__age__gt=20}/Q{seller__detail__age__gt=20}}
Record:where{Q{buyer__detail__info__weight__gt=20}/Q{seller__detail__info__height__gt=20}}
Record:where{Q{seller__detail__info__weight__gt=20}/Q{buyer__detail__info__height__gt=20}, buyer__detail__info__height__lt=120}:join{'buyer'}
Record:where{Q{seller__detail__info__weight__gt=20}/Q{buyer__detail__info__height__gt=20}, buyer__detail__info__height__lt=120}:join{'buyer', 'seller', 'product'}

]]

for e in statement_string:gmatch('[^\n]+') do
    render_to_browser(e)
end
