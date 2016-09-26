-- https://docs.djangoproject.com/en/1.10/ref/forms/widgets/#django.forms.SelectMultiple
local utils = require"resty.mvc.utils"
local string_format = string.format
local pairs = pairs
local setmetatable = setmetatable
local assert = assert
local table_insert = table.insert
local table_concat = table.concat
local table_remove = table.remove

local Widget = {multipart=false}
function Widget.new(cls, init)
    init = init or {}
    cls.__index = cls
    return setmetatable(init, cls)
end
function Widget.instance(cls, attrs)
    local self = cls:new()
    if attrs ~= nil then
        self.attrs = utils.dict(attrs)
    else
        self.attrs = {}
    end
    self.is_instance = true
    return self
end
function Widget.is_hidden(self)
    if self.type then 
        return self.type == 'hidden' 
    end
    return false
end
function Widget.render(self, name, value, attrs)
    assert(nil, 'subclasses of Widget must provide a render() method')
end
function Widget.build_attrs(self, extra_attrs, kwargs)
    return utils.dict(self.attrs, extra_attrs, kwargs)
end
function Widget.value_from_datadict(self, data, files, name)
    return data[name]
end
function Widget.id_for_label(self, id)
    return id
end

local Input = Widget:new{type=false}
function Input._format_value(self, value)
    return value
end
function Input.render(self, name, value, attrs)
    if not value then
        value = ''
    end
    local final_attrs = self:build_attrs(attrs, {type=self.type, name=name})
    if value ~= '' then
        final_attrs['value'] = self:_format_value(value)
    end
    return string_format('<input%s />', utils.to_html_attrs(final_attrs))
end

local TextInput = Input:new{type='text'}

local NumberInput = Input:new{type='number'}

local EmailInput = Input:new{type='email'}

local URLInput = Input:new{type='url'}

local HiddenInput = Input:new{type='hidden'}

local PasswordInput = Input:new{type='password', render_value=false}
function PasswordInput.render(self, name, value, attrs)
    if not self.render_value then
        value = nil
    end
    return Input.render(self, name, value, attrs)
end

local FileInput = Input:new{type='file', multipart=true}
function FileInput.render(self, name, value, attrs)
    return Input.render(self, name, nil, attrs)
end
function FileInput.value_from_datadict(self, data, files, name)
    return files[name]
end

local Textarea = Widget:new{default_attrs={cols=40, rows=10}}
function Textarea.instance(cls, attrs)
    return Widget.instance(cls, utils.dict(cls.default_attrs, attrs))
end
function Textarea.render(self, name, value, attrs)
    if not value then
        value = ''
    end
    local final_attrs = self:build_attrs(attrs, {name=name})
    -- todo: is value need to escapte double quote? -- value:gsub('"', '&quot;')
    return string_format('<textarea%s>\n%s</textarea>', utils.to_html_attrs(final_attrs), value)
end

local DateInput = TextInput:new{format_key=''}

local DateTimeInput = TextInput:new{format_key=''}

local TimeInput = TextInput:new{format_key=''}

local CheckboxInput = Widget:new{}
function CheckboxInput.value_from_datadict(self, data, files, name)
    local value = data[name]
    if not value or value == '' or value =='0' or value=='false' then
        return false
    end
    return true
end
function CheckboxInput.render(self, name, value, attrs)
    local final_attrs = self:build_attrs(attrs, {type='checkbox', name=name})
    if not (value==0 or value==false or value==nil or value =='') then
        final_attrs.checked = 'checked'
    end
    -- if not (value==true or value==false or value==nil or value =='') then
    --     final_attrs.value = value
    -- end 
    return string_format('<input%s />', utils.to_html_attrs(final_attrs))
end

local Select = Widget:new{allow_multiple_selected=false}
function Select.instance(cls, attrs, choices)
    local self = Widget.instance(cls, attrs)
    self.choices = choices or {}
    return self
end
function Select.render(self, name, value, attrs, choices)
    choices = choices or {}
    if not value then
        value = ''
    end
    local final_attrs = self:build_attrs(attrs, {name=name})
    return string_format('<select%s>%s</select>', utils.to_html_attrs(final_attrs), 
        self:render_options(choices, {value}))
end
function Select.render_options(self, choices, selected_choices)
    local output = {}
    local choices_from_field = self.field and self.field.choices or {}
    for i,v in ipairs(utils.list(choices_from_field, self.choices, choices)) do
        local option_value, option_label = v[1], v[2]
        if type(option_label) == 'table' then
            table_insert(output, string_format('<optgroup label="%s">', option_value))
            for i, option in ipairs(option_label) do
                table_insert(output, self:render_option(selected_choices, option[1], option[2]))
            end
            table_insert(output,'</optgroup>')
        else
            table_insert(output, self:render_option(selected_choices, option_value, option_label))
        end
    end
    return table_concat(output, '\n')
end
function Select.render_option(self, selected_choices, option_value, option_label)
    if option_value == nil then
        option_value = ''
    end
    local selected = false
    local j
    for i, v in ipairs(selected_choices) do
        if v == option_value then
            selected = true
            j = i
            break
        end
    end
    local selected_html = ''
    if selected then
        selected_html = ' selected="selected"'
        if not self.allow_multiple_selected then
            -- why remove?
            -- Only allow for a single selection.
            -- loger('before:', selected_choices)
            table_remove(selected_choices, j)
            -- loger('after:', selected_choices)
        end
    end
    return string_format('<option value="%s"%s>%s</option>', 
        option_value, selected_html, option_label)
end

local SelectMultiple = Select:new{allow_multiple_selected=true}
function SelectMultiple.render(self, name, value, attrs, choices)
    -- 待定, reqargs将多选下拉框解析成的值是, 没选时直接忽略, 选1个的时候是字符串, 大于1个是table
    choices = choices or {}
    if not value then
        value = {}
    elseif type(value) == 'string' then
        value = {value}
    end
    local final_attrs = self:build_attrs(attrs, {name=name})
    return string_format('<select multiple="multiple"%s>%s</select>', utils.to_html_attrs(final_attrs), 
        self:render_options(choices, value))
end
-- function SelectMultiple.value_from_datadict(self, data, files, name)
--     -- 待定, OpenResy似乎无此问题, 直接从data读取即可
--     return data[name]
-- end

local ChoiceInput = {type=nil}
-- An object used by ChoiceFieldRenderer that represents a single
-- <input type='$input_type'>.
function ChoiceInput.new(cls, self)
    self = self or {}
    cls.__index = cls
    return setmetatable(self, cls)
end
function ChoiceInput.instance(cls, name, value, attrs, choice, index)
    local self = cls:new()
    self.name = name
    self.value = value
    self.attrs = attrs
    self.choice_value = choice[1]
    self.choice_label = choice[2]
    self.index = index
    if attrs.id then
        self.attrs.id = string_format('%s_%s',  attrs.id, self.index)
    end
    return self
end
function ChoiceInput.render(self, name, value, attrs, choices)
    choices = choices or {}
    local label_for = ''
    if self.attrs.id then
        label_for = string_format(' for="%s"', self.attrs.id)
    end
    if attrs then
        attrs = utils.dict(self.attrs, attrs)
    else
        attrs = self.attrs
    end
    return string_format('<label%s>%s %s</label>', label_for, self:tag(attrs), self.choice_label)
end
function ChoiceInput.tag(self, attrs)
    attrs = attrs or self.attrs
    local final_attrs = dict(attrs, {type=self.type, name=self.name, value=self.choice_value})
    if self:is_checked() then
        final_attrs.checked = 'checked'
    end
    return string_format('<input%s />', utils.to_html_attrs(final_attrs))
end
function ChoiceInput.is_checked(self)
    return self.value == self.choice_value
end

local RadioChoiceInput = ChoiceInput:new{type='radio'}

local CheckboxChoiceInput = ChoiceInput:new{type='checkbox'}
function CheckboxChoiceInput.is_checked(self)
    for i, v in ipairs(self.value) do
        if v == self.choice_value then
            return true
        end
    end
    return false
end

local ChoiceFieldRenderer = {choice_input_class=nil, 
    outer_html = '<ul%s>\n%s\n</ul>',  inner_html = '<li>%s%s</li>', }
function ChoiceFieldRenderer.new(cls, self)
    self = self or {}
    cls.__index = cls
    return setmetatable(self, cls)
end
function ChoiceFieldRenderer.instance(cls, name, value, attrs, choices)
    local self = cls:new()
    self.name = name
    self.value = value
    self.attrs = attrs
    self.choices = choices
    return self
end
function ChoiceFieldRenderer.render(self)
    -- Outputs a <ul> for this set of choice fields.
    -- If an id was given to the field, it is applied to the <ul> (each
    -- item in the list will get an id of `$id_$i`).
    local id = self.attrs.id
    local output = {}
    for i, choice in ipairs(self.choices) do
        local choice_value, choice_label = choice[1], choice[2]
        local attrs = dict(self.attrs)
        if type(choice_label)=='table' then
            if id then
                attrs.id = attrs.id..'_'..i
            end
            local sub_ul_renderer = ChoiceFieldRenderer:instance(self.name, self.value, attrs, choice_label)
            sub_ul_renderer.choice_input_class = self.choice_input_class
            table_insert(output, string_format(self.inner_html, choice_value, sub_ul_renderer:render()))
        else
            local w = self.choice_input_class:instance(self.name, self.value, attrs, choice, i)
            table_insert(output, string_format(self.inner_html, w:render(), ''))
        end
    end
    local id_attr = ''
    if id then
        id_attr = string_format(' id="%s"', id)
    end
    return string_format(self.outer_html, id_attr, table_concat(output, '\n'))
end

local RadioFieldRenderer = ChoiceFieldRenderer:new{choice_input_class=RadioChoiceInput}

local CheckboxFieldRenderer = ChoiceFieldRenderer:new{choice_input_class=CheckboxChoiceInput}  

local RendererMixin = {renderer=nil, _empty_value=nil}
function RendererMixin.get_renderer(self, name, value, attrs, choices)
    -- Returns an instance of the renderer.
    -- big different from Django: use `self.field.choices` instead of `self.choices`
    local choices_from_field = self.field and self.field.choices or {}
    choices = utils.list(choices_from_field, self.choices, choices)
    if value == nil then
        value = self._empty_value
    end
    local final_attrs = self:build_attrs(attrs)
    return self.renderer:instance(name, value, final_attrs, choices)
end
function RendererMixin.render(self, name, value, attrs, choices)
    return self:get_renderer(name, value, attrs, choices):render()
end
function RendererMixin.id_for_label(self, id)
    -- # Widgets using this RendererMixin are made of a collection of
    -- # subwidgets, each with their own <label>, and distinct ID.
    -- # The IDs are made distinct by y "_X" suffix, where X is the zero-based
    -- # index of the choice field. Thus, the label for the main widget should
    -- # reference the first subwidget, hence the "_0" suffix.
    -- <label for="id_xb_0">性别:</label>
    -- <ul id="id_xb">
        -- <li><label for="id_xb_0"><input id="id_xb_0" name="xb" type="radio" value="男" /> 男</label></li>
        -- <li><label for="id_xb_1"><input id="id_xb_1" name="xb" type="radio" value="女" /> 女</label></li>
    -- </ul>
    if id then
        id = id..'_1'
    end
    return id
end

local RadioSelect = Select:new{renderer=RadioFieldRenderer, _empty_value=''}
for k,v in pairs(RendererMixin) do
    RadioSelect[k] = v
end

local CheckboxSelectMultiple = SelectMultiple:new{renderer=CheckboxFieldRenderer, _empty_value={}}
for k,v in pairs(RendererMixin) do
    CheckboxSelectMultiple[k] = v
end

return {
    Widget = Widget, 
    TextInput = TextInput, 
    EmailInput = EmailInput, 
    URLInput = URLInput, 
    NumberInput = NumberInput, 
    PasswordInput = PasswordInput, 
    HiddenInput = HiddenInput, 
    FileInput = FileInput, 
    Textarea = Textarea, 
    CheckboxInput = CheckboxInput, 

    DateInput = DateInput, 
    DateTimeInput = DateTimeInput, 
    TimeInput = TimeInput, 

    Select = Select, 
    RadioSelect = RadioSelect, 
    SelectMultiple = SelectMultiple --to do

}