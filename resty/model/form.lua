local rawget = rawget
local setmetatable = setmetatable
local ipairs = ipairs
local tostring = tostring
local type = type
local pairs = pairs
local string_format = string.format
local table_concat = table.concat

local function ClassCaller(cls, attrs)
    return cls:new(attrs):_resolve_fields()
end
local function InstanceCaller(cls, attrs)
    return cls:init(attrs)
end

local Form = setmetatable({}, {__call=ClassCaller})
Form.row_template = [[<div> %s %s %s %s </div>]]
Form.error_template = [[<ul class="error">%s</ul>]]
Form.help_template = [[<p class="help">%s</p>]]

function Form.new(self, attrs)
    attrs = attrs or {}
    self.__index = self
    self.__call = InstanceCaller
    return setmetatable(attrs, self)
end
function Form.class(cls, subclass)
    return cls:new(subclass):_resolve_fields()
end
function Form._resolve_fields(self)
    -- for sugar: the hash table form of field defination
    local fields = self.fields
    if not fields then -- no fields to resolve, just return
        return self
    end
    if fields[1]~=nil then -- array form
        if self.field_order == nil then
            local fo = {}
            for i,v in ipairs(fields) do
                fo[i] = v.name
            end
            self.field_order = fo
        end
    else --hash form, will be converted to array form
        if self.field_order == nil then
        	local fo = {}
        	for name, v in pairs(fields) do
        		fo[#fo+1] = name
        	end
        	self.field_order = fo
        end
        local final_fields = {}
        for name, field_maker in pairs(fields) do
        	final_fields[#final_fields+1] = field_maker{name=name}
        end
        self.fields = final_fields
    end
    return self
end
function Form.init(cls, attrs)
    local self = cls:new(attrs)
    self.is_bound = self.data or self.files
    self.data = self.data or {}
    self.files = self.files or {}
    self.initial = self.initial or {}
    self.label_suffix = self.label_suffix or ''
    -- make a child-copy of fields so we can safely dynamically overwrite 
    -- some attributes of the field, e.g. `choices` of OptionField
    local fields = {}
    for i, v in ipairs(self.fields) do 
    	fields[#fields+1] = v:new()
    end
    self.fields = fields
    return self
end
function Form.get_value(self, field)
	local name = field.name
    if self.is_bound then
    	return self.data[name] -- or self.files[name]
    elseif self.instance then
    	return self.instance[name]
    else
    	return field.initial or self.initial[name] or field.default
    end
end
function Form._get_field(self, name)
    for i,v in ipairs(self.fields) do
        if v.name == name then
            return v
        end
    end
end
function Form.render(self)
    local res = {}
    local has_error = self.has_error
    for i, name in ipairs(self.field_order) do
        local field = self:_get_field(name)
        if field then
            local errors_string = ''
            if has_error and self.errors[name] then
                for i, message in ipairs(self.errors[name]) do
                    errors_string = errors_string..'<li>'..message..'</li>'
                end
                errors_string = string_format(self.error_template, errors_string)
            end
            local help_text_string = ''
            if field.help_text then
                help_text_string = string_format(self.help_template, field.help_text)
            end
            local attrs = field:get_base_attrs()
            res[#res+1] = string_format(
                self.row_template, 
                field.label_html, 
                field:render(self:get_value(field), attrs), 
                errors_string, help_text_string)
        end
    end
    return table_concat(res, "\n")
end
function Form.get_errors(self)
    if not self.errors then
        self:full_clean()
    end
    return self.errors
end
function Form.is_valid(self)
    self:get_errors()
    return self.is_bound and not self.has_error
end
function Form._clean_fields(self)
    for i, name in ipairs(self.field_order) do
        local field = self:_get_field(name)
        local value = self.data[name] or self.files[name]
        local value, errors = field:clean(value)
        if errors then
            self.has_error = true
            self.errors[name] = errors
        else
            self.cleaned_data[name] = value
            local clean_method = self['clean_'..name]
            if clean_method then
                value, errors = clean_method(self, value)
                if errors then
                    self.has_error = true
                    self.errors[name] = errors
                else
                    self.cleaned_data[name] = value
                end
            end
        end
    end
end
function Form._clean_form(self)
    local cleaned_data, errors = self:clean()
    if errors then
        self.has_error = true
        self.errors['__all__'] = errors
    elseif cleaned_data then
        self.cleaned_data = cleaned_data
    end
end
function Form.clean(self)
    return self.cleaned_data
end
function Form.full_clean(self)
    self.errors = {}
    self.cleaned_data = {}
    self:_clean_fields()
    self:_clean_form()
end
function Form.save(self)
    -- local res = {}
end
return Form