local rawget = rawget
local setmetatable = setmetatable
local getmetatable = getmetatable
local ipairs = ipairs
local tostring = tostring
local type = type
local pairs = pairs
local string_format = string.format
local table_concat = table.concat

local Form = {field_order=nil, prefix=nil}
Form.row_template = [[<div%s>%s%s%s%s</div>]]
Form.error_list_template = [[<ul class="error">%s</ul>]]
Form.error_template = [[<li>%s</li>]]
Form.help_text_html = [[<p class="help">%s</p>]]

function Form.new(self, attrs)
    attrs = attrs or {}
    self.__index = self
    return setmetatable(attrs, self)
end
function Form.class(cls, subclass)
    -- do some extra work after `new`
    local subclass = cls:new(subclass)
    if not subclass.field_order then
        local field_order = {}
        for k, v in pairs(subclass.fields) do
            field_order[#field_order+1] = k
        end
        subclass.field_order = field_order
    end
    return subclass
end
function Form.instance(cls, attrs)
    local self = cls:new(attrs)
    self.auto_id = self.auto_id or 'id_%s'
    self.is_bound = self.data~=nil or self.files~=nil
    self.data = self.data or {}
    self.files = self.files or {}
    self.initial = self.initial or {}
    self.label_suffix = self.label_suffix or ''
    -- make instances of fields so we can safely dynamically overwrite 
    -- some attributes of the field, e.g. `choices` of ChoiceField
    local fields = {}
    for name, field_class in pairs(self.fields) do 
        fields[name] = field_class:new()
    end
    self.fields = fields
    self._bound_fields_cache = {}
    return self
end
function Form.get(self, name)
	local field = self.fields[name]
    if not field then
        return nil
    end
    if not self._bound_fields_cache[name] then
        self._bound_fields_cache[name] = field:get_bound_field(self, name)
    end
    return self._bound_fields_cache[name]
end
function Form.add_prefix(self, field_name)
    -- """
    -- Returns the field name with a prefix appended, if this Form has a
    -- prefix set.

    -- Subclasses may wish to override.
    -- """
    if self.prefix then
        return string_format('%s-%s', self.prefix, field_name)
    end
    return field_name
end
function Form.render(self)
    local res = {}
    local html_class_attr = ''
    local label = ''
    local help_text = ''
    for i, name in ipairs(self.field_order) do
        local bf = self:get(name)
        if bf:is_hidden() then
            res[#res+1] = bf:render()
        else
            local css_classes = bf:css_classes()
            if css_classes and css_classes~='' then
                html_class_attr = string_format(' class="%s"', css_classes)
            end
            if bf.label then
                label = bf:label_tag(bf.label) or ''
            end
            if bf.help_text then
                help_text = string_format(self.help_text_html, bf.help_text)
            end
            local error_html = ''
            local errors = bf:errors()
            if errors then
                for i,v in ipairs(errors) do
                    errors[i] = string_format(self.error_template, v)
                end
                error_html = string_format(self.error_list_template, table_concat(errors, '\n'))
            end
-- Form.error_template = [[<ul class="error">%s</ul>]]
-- Form.help_text_html = [[<p class="help">%s</p>]]
-- Form.row_template = [[<div%s>%s%s%s%s</div>]]
            res[#res+1] = string_format(self.row_template, html_class_attr, label, error_html, bf:render(), help_text)
        end
    end
    return table_concat(res, "\n")
end
function Form.errors(self)
    if not self._errors then
        self:full_clean()
    end
    return self._errors
end
function Form.is_valid(self)
    return self.is_bound and next(self:errors()) == nil
end
function Form._clean_fields(self)
    for i, name in ipairs(self.field_order) do
        local field = self.fields[name]
        local value;
        if field.disabled then
            value = self.initial[name] or field.initial
        else
            value = field.widget:value_from_datadict(self.data, self.files, self:add_prefix(name))
        end
        local value, errors = field:clean(value)
        if errors then
            self._errors[name] = errors
        else
            self.cleaned_data[name] = value
            local clean_method = self['clean_'..name]
            if clean_method then
                value, errors = clean_method(self, value)
                if errors then
                    self._errors[name] = errors
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
        self._errors['__all__'] = errors
    elseif cleaned_data then
        self.cleaned_data = cleaned_data
    end
end
function Form.clean(self)
    return self.cleaned_data
end
function Form.full_clean(self)
    self._errors = {}
    if self.is_bound then
        self.cleaned_data = {}
        self:_clean_fields()
        self:_clean_form()
    end
end
function Form.save(self)
    local ins = self.model_instance
    if ins then
        for k, v in pairs(self.cleaned_data) do
            ins[k] = v
        end
        local res, errors = ins:update_without_clean()
        if not res then
            return nil, errors
        end
        return ins
    elseif self.model then
        local new_ins = self.cleaned_data
        local res, errors = self.model:instance(new_ins):create_without_clean()
        if not res then
            return nil, errors
        end
        return new_ins
    else
        -- for consistent with Row:save and Model:create, error is returned as a table
        return nil, {'`model_instance` or `model` should be set'}
    end
end
return Form