local query = require"resty.mvc.query".single
local Validator = require"resty.mvc.validator"
local Widget = require"resty.mvc.widget"
local BoundField = require"resty.mvc.boundfield"
local datetime = require"resty.mvc.datetime".datetime
local utils = require"resty.mvc.utils"
local rawget = rawget
local setmetatable = setmetatable
local getmetatable = getmetatable
local ipairs = ipairs
local tostring = tostring
local type = type
local pairs = pairs
local assert = assert
local next = next
local string_format = string.format
local string_sub = string.sub
local table_concat = table.concat
local table_insert = table.insert
local math_floor = math.floor
local os_rename = os.rename
local ngx_re_gsub = ngx.re.gsub
local ngx_re_match = ngx.re.match


local function ClassCaller(cls, attrs)
    return cls:instance(attrs)
end

local Field = {
    widget = Widget.TextInput, 
    hidden_widget = Widget.HiddenInput, 
    default_error_messages = {required='This field is required.'}, 
    required = true, 
}
setmetatable(Field, {__call=ClassCaller})
function Field.new(cls, self)
    -- supported options of self: 
    -- required, widget, label, initial, help_text, error_messages
    -- validators, disabled, label_suffix
    self = self or {}
    cls.__index = cls
    cls.__call = ClassCaller
    return setmetatable(self, cls)
end
function Field.instance(cls, attrs)
    -- used when defining a form
    local self = cls:new(attrs)
    local widget = self.widget 
    if not rawget(widget, 'is_instance') then
        widget = widget:instance()
    end
    -- big different from Django: widget gets access to field
    -- currently mainly for easy override of `choices` attribute of `Select` and `RadioSelect`
    widget.field = self 
    -- Let the widget know whether it should display as required.
    widget.is_required = self.required
    -- Hook into self.widget_attrs() for any Field-specific HTML attributes.
    utils.dict_update(widget.attrs, self:widget_attrs(widget))
    self.widget = widget
    -- walk parents
    local messages = {}
    for _, cls in ipairs(utils.reversed_inherited_chain(self)) do
        utils.dict_update(messages, cls.default_error_messages)
    end
    self.error_messages = messages
    self.validators = utils.list(self.default_validators, self.validators)
    return self
end
function Field.copy(self)
    -- used when make a form instance 
    local field = self:new()
    -- `widget` is a special attribute, mainly due to `choices` render logic
    field.widget = self.widget:new{field=field}
    return field
end
function Field.widget_attrs(self, widget)
    return {}
end
function Field.client_to_lua(self, value)
    return value
end
function Field.validate(self, value)
    if utils.is_empty_value(value) and self.required then
        return self.error_messages.required
    end
end
function Field.run_validators(self, value)
    if utils.is_empty_value(value) then
        return 
    end
    local errors = {}
    for i, validator in ipairs(self.validators) do
        local err = validator(value)
        if err then
            errors[#errors+1] = err
        end
    end
    if next(errors) then
        return errors
    end
end
function Field.clean(self, value)
    local value, err = self:client_to_lua(value)
    if value == nil and err ~= nil then
        return nil, {err}
    end
    -- validate
    local err = self:validate(value)
    if err then
        return nil, {err}
    end
    -- validators
    local errors = self:run_validators(value)
    if errors then
        return nil, errors
    end
    return value
end
function Field.bound_data(self, data, initial)
    if self.disable then
        return initial
    end
    return data
end
function Field.get_bound_field(self, form, field_name)
    return BoundField:instance(form, self, field_name)
end
function Field.prepare_value(self, value)
    -- hooks for changing boundfield value, used in widget:render method
    -- some special fields like ForeignKey and DateTimeField need this.
    return value
end


local CharField = Field:new{maxlen=nil, minlen=nil, strip=true}
function CharField.instance(cls, attrs)
    local self = Field.instance(cls, attrs) 
    if self.maxlen then 
        table_insert(self.validators, Validator.maxlen(self.maxlen))
    end
    if self.minlen then
        table_insert(self.validators, Validator.minlen(self.minlen))
    end
    return self
end
function CharField.client_to_lua(self, value)
    if utils.is_empty_value(value) then
        return ''
    end
    if self.strip then
        value = utils.string_strip(value)
    end
    return value
end
function CharField.widget_attrs(self, widget)
    local attrs = Field.widget_attrs(self, widget)
    if self.maxlen then
        attrs.maxlength = self.maxlen
    end
    if self.minlen then
        attrs.minlength = self.minlen
    end
    return attrs
end


local IntegerField = Field:new{widget=Widget.NumberInput, 
    default_error_messages = {invalid='Enter an interger.'}}
function IntegerField.instance(cls, attrs)
    local self = Field.instance(cls, attrs) 
    if self.max then
        table_insert(self.validators, Validator.max(self.max))
    end
    if self.min then
        table_insert(self.validators, Validator.min(self.min))
    end
    return self
end
function IntegerField.client_to_lua(self, value)
    if utils.is_empty_value(value) then
        return
    end
    value = tonumber(value)
    if not value or math_floor(value) ~= value then
        return nil, self.error_messages.invalid
    end
    return value
end
function IntegerField.widget_attrs(self, widget)
    local attrs = Field.widget_attrs(self, widget)
    if self.max then
        attrs.max = self.max
    end
    if self.min then
        attrs.min = self.min
    end
    return attrs
end


local FloatField = IntegerField:new{
    default_error_messages={invalid='Enter a float.'}, 
}
function FloatField.client_to_lua(self, value)
    if utils.is_empty_value(value) then
        return
    end
    value = tonumber(value)
    if not value then
        return nil, self.error_messages.invalid
    end
    return value
end
function FloatField.widget_attrs(self, widget)
    local attrs = IntegerField.widget_attrs(self, widget)
    if not widget.attrs.step then
        attrs.step = 'any'
    end
    return attrs
end


local BaseTemporalField = Field:new{format_re=nil}
function BaseTemporalField.client_to_lua(self, value)
    if utils.is_empty_value(value) then
        return
    end
    value = utils.string_strip(value)
    local res, err = ngx_re_match(value, self.format_re, 'jo')
    if not res then
        return nil, self.error_messages.invalid
    end
    return value
end

local DateTimeField = BaseTemporalField:new{
    widget = Widget.DateTimeInput, 
    default_error_messages = {
        invalid='Enter a valid datetime, e.g. 2010-01-01 09:30:00.', 
    }, 
    format_re = [[^(19|20)\d\d-(0?[1-9]|1[012])-(0?[1-9]|[12][0-9]|3[01]) [012]\d:[0-5]\d:[0-5]\d$]], 
}
function DateTimeField.client_to_lua(self, value)
    local res, err = BaseTemporalField.client_to_lua(self, value)
    if not res then
        return nil, err
    end
    return datetime.new(value) 
end

local DateField = BaseTemporalField:new{
    widget=Widget.DateInput, 
    default_error_messages = {
        invalid='Enter a valid date, e.g. 2010-01-01.', 
    }, 
    format_re = [[^(19|20)\d\d-(0?[1-9]|1[012])-(0?[1-9]|[12][0-9]|3[01])$]], 
}

local TimeField = BaseTemporalField:new{
    widget=Widget.TimeInput, 
    default_error_messages = {
        invalid='Enter a valid time, e.g. 09:30:00.', 
    }, 
    format_re = [[^[012]\d:[0-5]\d:[0-5]\d$]], 
}

local HiddenField = CharField:new{widget=Widget.HiddenInput}

local PasswordField = CharField:new{widget=Widget.PasswordInput}

local EmailField = CharField:new{widget=Widget.EmailInput}

local URLField = CharField:new{widget=Widget.URLInput}

local TextareaField = CharField:new{widget=Widget.Textarea}

local BooleanField = Field:new{widget=Widget.CheckboxInput}
function BooleanField.client_to_lua(self, value)
    if value == 'on' then
        return true
    elseif value == nil or value =='0' or value == 0 or value == '' or value=='false' then
        return false
    elseif value == true or value == false then
        return value
    end
    return true
end
function BooleanField.validate(self, value)
    if not value and self.required then
        return self.error_messages.required
    end
end

local ChoiceField = Field:new{
    widget = Widget.Select, 
    default_error_messages = {
        invalid_choice = '%s is not one of the available choices.', 
    },
}
function ChoiceField.instance(cls, attrs)
    attrs.choices = attrs.choices or {}
    assert(type(attrs.choices) == 'table', "`choices` must be a table")
    for i, choice in ipairs(attrs.choices) do
        assert(type(choice) == 'table', 'the type of `choices` member must be table') 
        assert(#choice == 2, 'the length of `choices` member must be 2')
    end
    return Field.instance(cls, attrs)
end
function ChoiceField.client_to_lua(self, value)
    if utils.is_empty_value(value) then
        return 
    end
    return value
end
function ChoiceField.validate(self, value)
    local err = Field.validate(self, value)
    if err then
        return err
    end
    if value and not self:valid_value(value) then
        return string_format(self.error_messages.invalid_choice, value)
    end
end
function ChoiceField.valid_value(self, value)
    for i, e in ipairs(self.choices) do
        local k, v = e[1], e[2]
        if type(v) == 'table' then
            -- This is an optgroup, so look inside the group for options
            for i, e in ipairs(v) do
                local k2, v2 = e[1], e[2]
                if value == k2 or  value == tostring(k2) then
                    return true
                end
            end
        else
            -- todo this is a simple version of checking.
            -- because TypedChoiceField is not used.
            if value == k or value == tostring(k) then
                return true
            end
        end
    end
    return false
end

-- file api is based on lua-resty-reqargs
local FileField = Field:new{upload_to=nil}
function FileField.instance(cls, attrs)
    local self = Field.instance(cls, attrs)
    self.upload_to = self.upload_to or 'static/files/' -- assert(nil, 'upload_to is required for FileField')
    local last_char = string_sub(self.upload_to, -1, -1)
    if last_char ~= '/' and last_char ~= '\\' then
        self.upload_to = self.upload_to..'/'
    end
    return self
end
function FileField.validate(self, value)
    return Field.validate(self, value.file)
end
function FileField.clean(self, value)
    local value, errors = Field.clean(self, value) 
    if errors then
        -- currently don't need to delete the error file because of `middlewares.post`
        -- os_remove(value.temp) 
        return nil, errors
    end
    value.save_path = self.upload_to..value.file
    os_rename(value.temp, value.save_path)
    return value
end

local ForeignKey = ChoiceField:new{
    limit_choices_to = nil,
    empty_label = nil,
}
function ForeignKey.instance(cls, attrs)
    local self = Field.instance(cls, attrs) -- not ChoiceField.instance because no need to check `choices`
    if self.required and self.initial ~= nil then
        self.empty_label = nil
    else
        self.empty_label = self.empty_label or "---------"
    end
    self.reference = self.reference or self[1] or assert(nil, 'a model must be provided for ForeignKey')
    local model = self.reference
    assert(model.meta.table_name and model.fields, 'It seems that you did not provide a model')
    return self
end
function ForeignKey.client_to_lua(self, value)
    if utils.is_empty_value(value) then
        return 
    end
    -- currently search by id
    local ins, err = self.reference:get{id=tonumber(value)}
    if ins == nil then
        return nil, string_format(self.error_messages.invalid_choice, value)
    end
    return ins
end
function ForeignKey.validate(self, value)
    -- because we already perform choice checks in `client_to_lua`, so here
    -- we need to overwrite `ChoiceField.validate`
    return Field.validate(self, value)
end
function ForeignKey.copy(self)
    local field = ChoiceField.copy(self)
    local fk_model = self.reference
    local choices
    if self.empty_label ~= nil then
        choices = {{'', self.empty_label}}
    else
        choices = {}
    end
    for i, e in ipairs(fk_model:where(self.limit_choices_to):exec()) do
        choices[#choices + 1] = {e.id, self:label_from_instance(e)}
    end
    field.choices = choices
    return field
end
function ForeignKey.prepare_value(self, value)
    if type(value) == 'table' then
        return value.id
    end
    return value
end
function ForeignKey.label_from_instance(self, obj)
    return obj.__model.render(obj)
end

local MultipleChoiceField = ChoiceField:new{
    widget = Widget.SelectMultiple, 
    default_error_messages = {
        invalid_choice='Select a valid choice. %s is not one of the available choices.',
        invalid_list='Enter a list of values.', 
    }, 
}
function MultipleChoiceField.client_to_lua(self, value)
    -- 待定, reqargs将多选下拉框解析成的值是, 没选时直接忽略, 选1个的时候是字符串, 大于1个是table
    if not value then
        return {}
    elseif type(value) =='string' then
        return {value}
    elseif type(value)~='table' then
        return nil, self.error_messages.invalid_list
    end
    return value
end
function MultipleChoiceField.validate(self, value)
    if self.required and next(value) == nil then
        return self.error_messages.required
    end
    -- Validate that each value in the value list is in self.choices.
    for _, val in ipairs(value) do
        if not self:valid_value(val) then
            return string_format(self.error_messages.invalid_choice, val)
        end
    end
end


return{
    CharField = CharField, 
    TextField = TextField, 
    PasswordField = PasswordField, 
    IntegerField = IntegerField, 
    FloatField = FloatField, 
    
    DateField = DateField, 
    DateTimeField = DateTimeField, 
    TimeField = TimeField, 
    
    ChoiceField = ChoiceField, 
    BooleanField = BooleanField, 
    HiddenField = HiddenField, 
    FileField = FileField, 

    ForeignKey = ForeignKey, 
    -- MultipleChoiceField = MultipleChoiceField, -- todo
}