    -- 'Field', 'CharField', 'IntegerField',
    -- 'DateField', 'TimeField', 'DateTimeField', 'DurationField',
    -- 'RegexField', 'EmailField', 'FileField', 'ImageField', 'URLField',
    -- 'BooleanField', 'NullBooleanField', 'ChoiceField', 'MultipleChoiceField',
    -- 'ComboField', 'MultiValueField', 'FloatField', 'DecimalField',
    -- 'SplitDateTimeField', 'GenericIPAddressField', 'FilePathField',
    -- 'SlugField', 'TypedChoiceField', 'TypedMultipleChoiceField', 'UUIDField',
local validator = require"resty.mvc.validator"
local rawget = rawget
local setmetatable = setmetatable
local ipairs = ipairs
local tostring = tostring
local type = type
local pairs = pairs
local assert = assert
local string_format = string.format
local string_sub = string.sub
local table_concat = table.concat
local table_insert = table.insert
local os_rename = os.rename

local gsub = ngx.re.gsub

local function _to_html_attrs(tbl)
    local res = {}
    for k,v in pairs(tbl) do
        res[#res+1] = string_format('%s="%s"', k, v)
    end
    return table_concat(res, " ")
end
local function ClassCaller(cls, attrs)
    return cls:maker(attrs)
end
local Field = setmetatable({id_prefix = 'id-',required = true}, {__call=ClassCaller})

function Field.new(self, attrs)
    attrs = attrs or {}
    self.__index = self
    self.__call = ClassCaller
    return setmetatable(attrs, self)
end
function Field.maker(cls, attrs)
    -- read attrs from model class or form class
    -- currently mainly for auto setting field.label 
    local function field_maker(extern_attrs)
        for k, v in pairs(extern_attrs) do
            attrs[k] = v
        end
        return cls:init(attrs)
    end
    return field_maker 
end
function Field.init(cls, attrs)
    local self = cls:new(attrs)
    self.id = self.id_prefix..self.name
    self.label = self.label or self[1] or self.name
    self.label_html = string_format('<label for="%s">%s%s</label>', self.id_prefix..self.name, self.label, self.label_suffix or '')
    -- if self.required == nil then
    --     self.required = true
    -- end
    --self.initial = self.initial or ''
    --self.help_text = self.help_text or ''
    --self.label_suffix = self.label_suffix or ''
    self.validators = self.validators or {}
    return self
end
function Field.get_base_attrs(self)
    local base_attrs = {id=self.id, name=self.name}
    if self.attrs then
        for k,v in pairs(self.attrs) do
            base_attrs[k] = v
        end   
    end 
    return base_attrs
end
function Field.render(self, value, attrs)

end
function Field.to_lua(self, value)
    return value
end
function Field.clean(self, value)
    value = self:to_lua(value)
    -- validate
    local err = self:validate(value)
    if err then
        return nil, {err}
    end
    -- validators
    local errors = {}
    local has_error;
    for i, validator in ipairs(self.validators) do
        err = validator(value)
        if err then
            has_error = true
            errors[#errors+1] = err
        end
    end
    if has_error then
        return nil, errors
    else
        return value
    end
end
function Field.validate(self, value)
    if (value == nil or value == '') and self.required then
        return 'this field is required.'
    end
end
-- function Field.run_validators(self, value)

--     return value
-- end
--<input id="id_sfzh" maxlength="18" name="sfzh" placeholder="" type="text">
--逻辑值 <input checked="checked" id="id_enable" name="enable" type="checkbox" />

local CharField = Field:new{template='<input %s />', type='text'}
function CharField.init(cls, attrs)
    local self = Field.init(cls, attrs) 
    self.maxlength = self.maxlength or assert(nil, 'maxlength is required for CharField')
    if self.strip == nil then
        self.strip = true
    end
    table_insert(self.validators, validator.maxlen(self.maxlength))
    --self.errors = {}
    return self
end
function CharField.to_lua(self, value)
    if not value then
        return ''
    end
    value = tostring(value)
    if self.strip then
        --value = string.gsub(value, '^%s*(.-)%s*$', '%1')
        value = gsub(value, '^\\s*(.+)\\s*$', '$1','jo')
    end
    return value
end
function CharField.render(self, value, attrs)
    attrs.maxlength = self.maxlength
    attrs.value = value
    attrs.type = self.type
    return string_format(self.template, _to_html_attrs(attrs))
end

local PasswordField = CharField:new{type='password'}

local IntegerField = Field:new{template='<input %s />', type='number'}
function IntegerField.init(cls, attrs)
    local self = Field.init(cls, attrs) 
    if self.max then
        table_insert(self.validators, validator.max(self.max))
    end
    if self.min then
        table_insert(self.validators, validator.min(self.min))
    end
    return self
end
function IntegerField.to_lua(self, value)
    return tonumber(value)
end
function IntegerField.render(self, value, attrs)
    attrs.max = self.max
    attrs.min = self.min
    attrs.value = value
    attrs.type = self.type
    return string_format(self.template, _to_html_attrs(attrs))
end

local TextField = Field:new{template='<textarea %s>%s</textarea>', attrs={cols=40, rows=6}}
function TextField.init(cls, attrs)
    local self = Field.init(cls, attrs)
    self.maxlength = self.maxlength or assert(nil, 'maxlength is required for TextField')
    table_insert(self.validators, validator.maxlen(self.maxlength))
    return self
end
-- function TextField.validate(self, value)
--     value = Field.validate(self, value)
--     return value
-- end
function TextField.render(self, value, attrs)
    attrs.maxlength = self.maxlength
    return string_format(self.template, _to_html_attrs(attrs), value or '')
end
-- <select id="id_model_name" name="model_name">
--  <option value="hetong" selected="selected">劳动合同制</option>
-- </select>

local OptionField = Field:new{template='<select %s>%s</select>', choice_template='<option %s>%s</option>', }
function OptionField.init(cls, attrs)
    local self = Field.init(cls, attrs)
    local choices = self.choices or assert(nil, 'choices is required for OptionField')
    local first=choices[1]
    if not first then
        assert(nil,'you must provide 1 choice at least')
    end
    if type(first)=='string' then
        self.choices={}
        for i,v in ipairs(choices) do
           self.choices[i]={v,v}
        end
    end
    return self
end
function OptionField.to_lua(self, value)
    if not value then
        return ''
    end
    return value
end
function OptionField.validate(self, value)
    local err = Field.validate(self, value)
    if err then
        return err
    end
    if value == nil or value == '' then
        return --this field is not required, passed
    end
    local valid = false
    for i, v in ipairs(self.choices) do
        if v[1]==value then
           valid=true
        end
    end
    if not valid then
        return 'invalid choice'
    end
end
function OptionField.render(self, value, attrs)
    local choices={}
    if value == nil or value =='' then
        choices[1]='<option value=""></option>'
    end
    for i, choice in ipairs(self.choices) do
        local db_val, val=choice[1], choice[2]
        local inner_attrs={value=db_val}
        if value==db_val then
            inner_attrs.selected="selected"
        end
        choices[#choices+1]=string_format(self.choice_template, _to_html_attrs(inner_attrs),val)
    end
    return string_format(self.template, _to_html_attrs(attrs), table_concat(choices,'\n'))
end
-- <ul id="id-name">
-- <li><label for="id-name-0"><input type="radio" value="-1" id="id-name-0" name="name" />拒绝</label></li>
-- <li><label for="id-name-1"><input type="radio" value="0"  id="id-name-1" name="name" checked="checked" />复原</label></li>
-- <li><label for="id-name-2"><input type="radio" value="1"  id="id-name-2" name="name" />通过</label></li>
-- </ul>
local RadioField = OptionField:new{template='<ul %s>%s</ul>',choice_template='<li><label %s><input %s />%s</label></li>',}
function RadioField.render(self, value, attrs)
    local choices={}
    for i, choice in ipairs(self.choices) do
        local db_val, val=choice[1], choice[2]
        local inner_id = attrs.id..'-'..i
        local inner_attrs={value=db_val, name=attrs.name, id=inner_id, type='radio'}
        if value==db_val then
            inner_attrs.checked="checked"
        end
        choices[#choices+1]=string_format(self.choice_template, _to_html_attrs({['for']=inner_id}), _to_html_attrs(inner_attrs), val)
    end
    return string_format(self.template, _to_html_attrs(attrs), table_concat(choices,'\n'))
end

local FileField = Field:new{template='<input %s />', type='file'}
function FileField.render(self, value, attrs)
    attrs.type = self.type
    return string_format(self.template, _to_html_attrs(attrs))
end
-- function FileField.to_lua(self, value)
--     return value.temp
-- end
-- empty file input needs to remove the file
-- {
--   "file": "",
--   "name": "avatar",
--   "size": 0,
--   "temp": "\s8rk.c",
--   "type": "application/octet-stream",},
function FileField.validate(self, value)
    local value = value.file
    if (value == nil or value == '') and self.required then
        return 'this field is required.'
    end 
end
function FileField.init(cls, attrs)
    local self = Field.init(cls, attrs)
    self.upload_to = self.upload_to or assert(nil, 'upload_to is required for FileField')
    local last_char = string_sub(self.upload_to, -1, -1)
    if last_char ~= '/' and last_char ~= '\\' then
        self.upload_to = self.upload_to..'/'
    end
    return self
end
function FileField.clean(self, value)
    local value, errors = Field.clean(self, value) 
    if errors then
        return nil, errors
    end
    value.save_path = self.upload_to..value.file
    os_rename(value.temp, value.save_path)
    return value
end

return{
    CharField = CharField, 
    IntegerField = IntegerField, 
    TextField = TextField, 
    RadioField = RadioField,
    OptionField = OptionField,
    PasswordField = PasswordField, 
    FileField = FileField, 
}