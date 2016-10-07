local query = require"resty.mvc.query".single
local Validator = require"resty.mvc.validator"
local FormField = require"resty.mvc.formfield"
local Widget = require"resty.mvc.widget"
local datetime = require"resty.mvc.datetime".datetime
local utils = require"resty.mvc.utils"
local rawget = rawget
local setmetatable = setmetatable
local ipairs = ipairs
local tostring = tostring
local type = type
local pairs = pairs
local assert = assert
local math_floor = math.floor
local string_format = string.format
local table_concat = table.concat
local table_insert = table.insert
local os_rename = os.rename
local ngx_re_gsub = ngx.re.gsub
local ngx_re_match = ngx.re.match

local function ClassCaller(cls, attrs)
    return cls:instance(attrs)
end

local Field = setmetatable({
    empty_strings_allowed = true,
    empty_values = {},
    default_validators = {},
    default_error_messages = {
        invalid_choice='%s is not a valid choice.',
        null='This field cannot be null.',
        blank='This field cannot be blank.',
        unique='This field already exists.',
    },
    hidden = false,
} , {__call=ClassCaller})

-- local NOT_PROVIDED = {}
function Field.new(cls, self)
    self = self or {}
    cls.__index = cls
    cls.__call = ClassCaller
    return setmetatable(self, cls)
end
function Field.instance(cls, attrs)
    -- widget stuff
    local self = cls:new(attrs)
    self.help_text = self.help_text or ''
    self.choices = self.choices -- or {}
    self.validators = utils.list(self.default_validators, self.validators)
    -- self.primary_key = self.primary_key or false
    self.blank = self.blank or false
    self.null = self.null or false
    self.db_index = self.db_index or false
    self.auto_created = self.auto_created or false
    if self.editable == nil then
        self.editable = true
    end
    if self.serialize == nil then
        self.serialize = true
    end
    self.unique = self.unique or false
    self.is_relation = self.remote_field ~= nil
    self.default = self.default 
    local messages = {}
    for parent in utils.reversed_metatables(self) do
        utils.dict_update(messages, parent.default_error_messages)
    end
    self.error_messages = utils.dict_update(messages, self.error_messages)
    return self
end
function Field.check(self, kwargs)
    errors = {}
    errors[#errors+1] = self:_check_field_name()
    errors[#errors+1] = self:_check_choices()
    errors[#errors+1] = self:_check_db_index()
    --errors[#errors+1] = self:_check_null_allowed_for_primary_keys()
    return errors
end
function Field._check_field_name(self)
    -- Check if field name is valid, i.e.
    -- 1) does not end with an underscore,
    -- 2) does not contain "__"
    -- 3) is not "pk"
    if self.name:match('_$') then
        return 'Field names must not end with an underscore.'
    elseif self.name:find('__') then
        return 'Field names must not contain "__".'
    elseif self.name == 'pk' then
        return "`pk` is a reserved word that cannot be used as a field name."
    end
end
function Field._check_choices(self)
    if self.choices then
        if type(self.choices) ~= 'table' then
            return "`choices` must be a table"
        end
        for i, choice in ipairs(self.choices) do
            if type(choice) ~= 'table' then
                return 'the type of `choices` member must be table'
            elseif #choice ~= 2 then
                return 'the length of `choices` member must be 2'
            end
        end
    end
end
function Field._check_db_index(self)
    if self.db_index ~= nil and self.db_index ~= true and self.db_index ~= false then
        return "`db_index` must be nil, true or false"
    end
end
-- function Field._check_null_allowed_for_primary_keys(self)
--     if self.primary_key and self.null then
--         return 'Primary keys must not have null=true.'
--     end
-- end
-- function Field.client_to_lua(self, value)
--     -- Converts the input value or value returned by lua-resty-mysql 
--     -- into the expected lua data type.
--     return value
-- end
-- function Field.lua_to_db(self, value)
--     -- get value prepared for database.
--     return value
-- end
function Field.run_validators(self, value)
    if utils.is_empty_value(value) then
        return
    end
    local errors = {}
    -- Currently use `validators` instead of `get_validators`
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
function Field.validate(self, value, model_instance)
    -- Validates value and throws ValidationError. Subclasses should override
    -- this to provide validation logic.
    if not self.editable then
        -- Skip validation for non-editable fields.
        return
    end
    if self.choices and not utils.is_empty_value(value) then
        for i, choice in ipairs(self.choices) do
            local option_key, option_value = choice[1], choice[2]
            if type(option_value) == 'table' then
                -- This is an optgroup, so look inside the group for options.
                for i, option in ipairs(option_value) do
                    local optgroup_key, optgroup_value = option[1], option[2]
                    if value == optgroup_key then
                        return
                    end
                end
            elseif value == option_key then
                return
            end
        end
        return string_format(self.error_messages.invalid_choice, value)
    end
    if not self.null and value == nil then
        return self.error_messages.null
    end
    if not self.blank and utils.is_empty_value(value) then
        return self.error_messages.blank
    end
end
function Field.clean(self, value, model_instance)
    local value, err = self:client_to_lua(value)
    if value == nil and err ~= nil then
        return nil, {err}
    end
    -- validate
    local err = self:validate(value, model_instance)
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
function Field.is_unique(self)
    return self.unique or self.primary_key
end
function Field.get_internal_type(self)
    return 'Field'
end
function Field.has_default(self)
    return self.default ~= nil
end
function Field.get_default(self)
    if self:has_default() then
        if type(self.default) == 'function' then
            return self:default()
        end
        return self.default
    end
    if not self.empty_strings_allowed or self.null then
        return
    end
    return ""
end
local BLANK_CHOICE_DASH = {{"", "---------"}}
function Field.get_choices(self, include_blank, blank_choice)
    -- Returns choices with a default blank choices included, for use
    -- as SelectField choices for this field.
    if include_blank == nil then
        include_blank = true
    end
    if blank_choice == nil then
        blank_choice = BLANK_CHOICE_DASH
    end
    local blank_defined = false
    local choices = utils.list(self.choices)
    local named_groups = next(choices)~=nil and type(choices[1][2])=='table'
    if not named_groups then
        for i = 1, #choices do
            local val = choices[i][1]
            if val == '' or val == nil then
                blank_defined = true
                break
            end
        end
    end
    local first_choice
    if include_blank and not blank_defined then
        first_choice = blank_choice
    else
        first_choice = {}
    end
    return utils.list(first_choice, choices)
end
function Field.get_choices_default(self)
    return self:get_choices()
end
local valid_typed_kwargs = {
    coerce = true,
    empty_value = true,
    choices = true,
    required = true,
    widget = true,
    label = true,
    initial = true,
    help_text = true,
    error_messages = true,
    show_hidden_initial = true,}
function Field.formfield(self, kwargs)
    local form_class = kwargs.form_class 
    local choices_form_class = kwargs.choices_form_class
    -- Returns a FormField instance for this database Field.
    local defaults = {required=not self.blank, label=self.verbose_name, help_text=self.help_text}
    if self:has_default() then
        if type(self.default) == 'function' then
            defaults.initial = self.default
            defaults.show_hidden_initial = true
        else
            defaults.initial = self:get_default()
        end
    end
    if self.choices then
        -- Fields with choices get special treatment.
        local include_blank = self.blank or not (self:has_default() or kwargs.initial~=nil)
        defaults.choices = self:get_choices(include_blank)
        -- defaults.coerce = self.client_to_lua
        if self.null then
            defaults.empty_value = nil
        end
        if choices_form_class ~= nil then
            form_class = choices_form_class
        else
            -- form_class = FormField.TypedChoiceField
            form_class = FormField.ChoiceField
        end
        -- Many of the subclass-specific formfield arguments (min_value,
        -- max_value) don't apply for choice fields, so be sure to only pass
        -- the values that TypedChoiceField will understand.
        for k, v in pairs(kwargs) do
            if not valid_typed_kwargs[k] then
                kwargs[k] = nil
            end
        end
    end
    utils.dict_update(defaults, kwargs)
    if form_class == nil then
        form_class = FormField.CharField
    end
    return form_class:instance(defaults)
end
function Field.flatchoices(self)
    -- """Flattened version of choices tuple."""
    local flat = {}
    for i, e in ipairs(self.choices) do
        local choice, value = e[1], e[2]
        if type(value) == 'table' then
            utils.list_extend(flat, value)
        else
            flat[#flat+1] = {choice, value}
        end
    end
    return flat
end


local CharField = Field:new{
    db_type = 'VARCHAR', 
    description = "String, 65535 characters at most",
}
function CharField.instance(cls, attrs)
    local self = Field.instance(cls, attrs)
    table_insert(self.validators, Validator.maxlen(self.maxlen))
    if self.minlen then
        table_insert(self.validators, Validator.minlen(self.minlen))
    end
    return self
end
function CharField.client_to_lua(self, value)
    if type(value) == 'string' or value == nil then
        return value
    end
    return tostring(value)
end
function CharField.lua_to_db(self, value)
    return self:client_to_lua(value)
end
function CharField.check(self, kwargs)
    local errors = Field.check(self, kwargs)
    errors[#errors+1] = self:_check_max_length_attribute(kwargs)
    return errors
end
function CharField._check_max_length_attribute(self, kwargs)
    if self.maxlen == nil then
        return "CharFields must define a 'maxlen' attribute."
    elseif not type(self.maxlen) == 'number' or self.maxlen <= 0 then
        return "'maxlen' must be a positive integer."
    elseif self.maxlen > 65535 then
        return "max length is 65535"
    end
end
function CharField.get_internal_type(self)
    return "CharField"
end
function CharField.formfield(self, kwargs)
    -- Passing maxlen to FormField.CharField means that the value's length
    -- will be validated twice. This is considered acceptable since we want
    -- the value in the form field (to pass into widget for example).
    local defaults = {maxlen = self.maxlen, minlen = self.minlen}
    if self.maxlen > 255 then
        -- bigger than 255 will be considered as a text field
        defaults.widget = Widget.Textarea
    end
    utils.dict_update(defaults, kwargs)
    return Field.formfield(self, defaults)
end


-- use CharField if mysql > 4.1
local TextField = Field:new{
    db_type = 'TEXT', 
    description = "Text, 65535 characters at most",
}
function TextField.instance(cls, attrs)
    local self = Field.instance(cls, attrs)
    if self.maxlen then
        table_insert(self.validators, Validator.maxlen(self.maxlen))
    end
    if self.minlen then
        table_insert(self.validators, Validator.minlen(self.minlen))
    end
    return self
end
function TextField.client_to_lua(self, value)
    if type(value) == 'string' or value == nil then
        return value
    end
    return tostring(value)
end
function TextField.lua_to_db(self, value)
    return self:client_to_lua(value)
end
function TextField.get_internal_type(self)
    return "TextField"
end
function TextField.formfield(self, kwargs)
    -- Passing maxlen to FormField.CharField means that the value's length
    -- will be validated twice. This is considered acceptable since we want
    -- the value in the form field (to pass into widget for example).
    local defaults = {maxlen = self.maxlen, minlen = self.minlen, widget=Widget.Textarea}
    utils.dict_update(defaults, kwargs)
    return Field.formfield(self, defaults)
end


local DateTimeCheckMixin = {}
function DateTimeCheckMixin.check(self, kwargs)
    local errors = Field.check(self, kwargs)
    errors[#errors+1] = self:_check_mutually_exclusive_options()
    errors[#errors+1] = self:_check_fix_default_value()
    return errors
end
function DateTimeCheckMixin._check_mutually_exclusive_options(self)
    -- auto_now, auto_now_add, and default are mutually exclusive
    -- options. The use of more than one of these options together
    -- will trigger an Error
    local default = self:has_default()
    if (self.auto_now_add and self.auto_now) or (self.auto_now_add and default)
        or (default and self.auto_now) then
        return "The options auto_now, auto_now_add, and default are mutually exclusive"
    end
end
function DateTimeCheckMixin._check_fix_default_value(self)
    return 
end

-- [[^(19|20)\d\d-(0?[1-9]|1[012])-(0?[1-9]|[12][0-9]|3[01])$]]
local DateField = Field:new{
    db_type = 'DATE', 
    description = "Date (without time)", 
    format_re = [[^\d{4}-(0?[1-9]|1[012])-(0?[1-9]|[12][0-9]|3[01])$]], 
    empty_strings_allowed = false, 
    default_error_messages = {
        invalid="Enter a valid date, e.g. 2010-01-01.",
        invalid_date="invalid date.",
    }, 
}
utils.dict_update(DateField, DateTimeCheckMixin)
function DateField.instance(cls, attrs)
    local self = Field.instance(cls, attrs)
    if self.auto_now or self.auto_now_add then
        self.editable = false
        self.blank = true
    end
    return self
end
function DateField._check_fix_default_value(self)

end
function DateField.get_internal_type(self)
    return "DateField"
end
function DateField.client_to_lua(self, value)
    if value == nil then
        return nil
    end
    value = tostring(value)
    local res, err = ngx_re_match(value, self.format_re, 'jo')
    if not res then
        return nil, self.error_messages.invalid
    end
    return value
end
function DateField.lua_to_db(self, value)
    return self:client_to_lua(value)
end
function DateField.formfield(self, kwargs)
    local defaults = {form_class=FormField.DateField}
    utils.dict_update(defaults, kwargs)
    return Field.formfield(self, defaults)
end

local DateTimeField = DateField:new{
    db_type = 'DATETIME', 
    format_re = [[^\d{4}-(0?[1-9]|1[012])-(0?[1-9]|[12][0-9]|3[01]) [012]\d:[0-5]\d:[0-5]\d$]], 
    empty_strings_allowed = false, 
    default_error_messages = {
        invalid="Enter a valid datetime, e.g. 2010-01-01 09:30:00.",
        invalid_date="invalid datetime.",
    }, 
    description = "Date (with time)", 
}
utils.dict_update(DateTimeField, DateTimeCheckMixin)
function DateTimeField.db_to_lua(self, value)
    return datetime.new(value)
end
function DateTimeField.lua_to_db(self, value)
    if type(value)~='string' then
        value = value.string
    end
    return value
end
function DateTimeField._check_fix_default_value(self)

end
function DateTimeField.get_internal_type(self)
    return "DateTimeField"
end
function DateTimeField.formfield(self, kwargs)
    local defaults = {form_class = FormField.DateTimeField}
    utils.dict_update(defaults, kwargs)
    return DateField.formfield(self, defaults)
end


local TimeField = Field:new{
    db_type = 'TIME', 
    format_re = [[^[012]\d:[0-5]\d:[0-5]\d$]], 
    empty_strings_allowed = false, 
    default_error_messages = {
        invalid= "Enter a valid time, e.g. 09:30:00.",
        invalid_time = "invalid time format",
    }, 
    description = "Time", 
}
utils.dict_update(TimeField, DateTimeCheckMixin)
function TimeField.instance(cls, attrs)
    local self = Field.instance(cls, attrs)
    if self.auto_now or self.auto_now_add then
        self.editable = false
        self.blank = true
    end
    return self
end
function TimeField.get_internal_type(self)
    return "TimeField"
end
function TimeField.client_to_lua(self, value)
    if value == nil then
        return nil
    end
    value = tostring(value)
    local res, err = ngx_re_match(value, self.format_re, 'jo')
    if not res then
        return nil, self.error_messages.invalid
    end
    return value
end
function TimeField.lua_to_db(self, value)
    -- todo
    return self:client_to_lua(value)
end
function TimeField.formfield(self, kwargs)
    local defaults = {form_class=FormField.TimeField}
    utils.dict_update(defaults, kwargs)
    return Field.formfield(self, defaults)
end


local EmailField = CharField:new{
    default_validators = {Validator.validate_email}, 
    description = "Email address" , 
}
function EmailField.instance(cls, attrs)
    -- maxlen=254 to be compliant with RFCs 3696 and 5321
    attrs.maxlen = attrs.maxlen or 254
    return CharField.instance(cls, attrs)
end
function EmailField.formfield(self, kwargs)
    -- As with CharField, this will cause email validation to be performed twice.
    local defaults = { form_class = FormField.EmailField}
    utils.dict_update(defaults, kwargs)
    return CharField.formfield(self, defaults)
end


local IntegerField = Field:new{
    db_type = 'INT', 
    empty_strings_allowed = false, 
    default_error_messages = {
        invalid = "value must be an integer.",
    }, 
    description = "Integer", 
}
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
    if value == nil then
        return nil
    end
    value = tonumber(value)
    if not value or math_floor(value) ~= value then
        return nil, self.error_messages.invalid
    end
    return value
end
function IntegerField.lua_to_db(self, value)
    if value == nil then
        return nil
    end
    return math_floor(value)
end
function IntegerField.check(self, kwargs)
    local errors = Field.check(self, kwargs)
    errors[#errors+1] = self:_check_max_length_warning()
    return errors
end
function IntegerField._check_max_length_warning(self)
    if self.maxlen ~= nil then
        return "'maxlen' is ignored when used with IntegerField"
    end
end
function IntegerField.get_internal_type(self)
    return "IntegerField"
end
function IntegerField.formfield(self, kwargs)
    local defaults = { min=self.min, max=self.max, 
        form_class=FormField.IntegerField,}
    utils.dict_update(defaults, kwargs)
    return Field.formfield(self, defaults)
end


local FloatField = Field:new{
    db_type = 'FLOAT', 
    empty_strings_allowed = false, 
    default_error_messages = {
        invalid = "value must be a float.",
    }, 
    description = "Floating point number", 
}
function FloatField.instance(cls, attrs)
    local self = Field.instance(cls, attrs)
    if self.max then
        table_insert(self.validators, Validator.max(self.max))
    end
    if self.min then
        table_insert(self.validators, Validator.min(self.min))
    end
    return self
end
function FloatField.client_to_lua(self, value)
    if value == nil then
        return nil
    end
    value = tonumber(value)
    if not value then
        return nil, self.error_messages.invalid
    end
    return value
end
function FloatField.lua_to_db(self, value)
    return tonumber(value)
end
function FloatField.get_internal_type(self)
    return "FloatField"
end
function FloatField.formfield(self, kwargs)
    local defaults = { min = self.min, max = self.max, 
        form_class = FormField.FloatField}
    utils.dict_update(defaults, kwargs)
    return Field.formfield(self, defaults)
end


local AutoField = Field:new{
    db_type = 'INT', 
    description = "Primary Key, from 0 to 4294967295.",
    empty_strings_allowed = false,
    default_error_messages = {
        invalid = "value must be an integer.",
    },
}
function AutoField.instance(cls, attrs)
    attrs.blank = true
    return Field.instance(cls, attrs)
end
function AutoField.check(self, kwargs)
    local errors = Field.check(self, kwargs)
    errors[#errors+1] = self:_check_primary_key()
    return errors
end
function AutoField._check_primary_key(self)
    if not self.primary_key then
        return 'AutoFields must set primary_key=true.'
    end
end
function AutoField.get_internal_type(self)
    return "AutoField"
end
function AutoField.client_to_lua(self, value)
    if value == nil then
        return nil
    end
    value = tonumber(value)
    if not value or math_floor(value) ~= value then
        return nil, self.error_messages.invalid
    end
    return value
end
function AutoField.lua_to_db(self, value)
    -- e.g. 12.0, 12.01, '12.0', '12.01' will be 12
    if value == nil then
        return nil
    end
    return math_floor(value)
end
function AutoField.validate(self, value, model_instance)
    return
end
function AutoField.formfield(self, kwargs)
    return nil
end


local BooleanField = Field:new{
    db_type = 'TINYINT', 
    description = "Boolean (Either true or false)",
    empty_strings_allowed = false,
    default_error_messages = {
        invalid = "value must be either true or false.",
    },
}
function BooleanField.instance(cls, attrs)
    attrs.blank = true
    return Field.instance(cls, attrs)
end
local BOOLEAN_TABLE = {
    [true] = true, 
    [false] = false, 
    ['1'] = true, 
    ['0'] = false, 
    [1] = true, 
    [0] = false, 
    ['true'] = true, 
    ['false'] = false, 
}
function BooleanField.client_to_lua(self, value)
    value = BOOLEAN_TABLE[value]
    if value ~= nil then
        return value
    end
    return nil, self.error_messages.invalid
end
function BooleanField.lua_to_db(self, value)
    value = BOOLEAN_TABLE[value]
    if not value then
        return 0
    else
        return 1
    end
end
function BooleanField.check(self, kwargs)
    local errors = Field.check(self, kwargs)
    errors[#errors+1] = self:_check_null(kwargs)
    return errors
end
function BooleanField._check_null(self, kwargs)
    if self.null then
        return 'BooleanFields do not accept null values.'
    end
end
function BooleanField.get_internal_type(self)
    return "BooleanField"
end
function BooleanField.formfield(self, kwargs)
    -- Unlike most fields, BooleanField figures out include_blank from
    -- self.null instead of self.blank.
    local defaults
    if self.choices then
        local include_blank = not (self:has_default() or kwargs.initial~=nil)
        defaults = {choices = self:get_choices(include_blank)}
    else
        defaults = {form_class = FormField.BooleanField}
    end
    utils.dict_update(defaults, kwargs)
    return Field.formfield(self, defaults)
end

local function __index(t, key)
    local res, err = query(string_format('select * from `%s` where id=%s;', t.__ref.table_name, t.id))
    if not res or res[1] == nil then
        return nil
    end
    for k, v in pairs(res[1]) do
        if rawget(t, k) == nil then
            t[k] = v
        end
    end
    t.__ref.row_class:instance(t)
    return t[key]
end
local FK_meta = {__index = __index}
local ForeignKey = Field:new{
    db_type = 'INT', 
    on_delete=nil, on_update=nil}
function ForeignKey.get_internal_type(self)
    return "ForeignKey"
end
function ForeignKey.db_to_lua(self, value)
    return setmetatable({id=value, __ref=self.reference}, FK_meta)
end
function ForeignKey.lua_to_db(self, value)
    return value.id
end
function ForeignKey.instance(cls, attrs)
    local self = cls:new(attrs)
    self.reference = self.reference or self[1] or assert(nil, 'a model name must be provided for ForeignKey')
    local e = self.reference
    assert(e.table_name and e.fields, 'It seems that you did not provide a model')
    self.validators = self.validators or {}
    return self
end


return {
    CharField = CharField,
    TextField = TextField,
    IntegerField = IntegerField,
    FloatField = FloatField,

    DateField = DateField,
    DateTimeField = DateTimeField,
    TimeField = TimeField,

    BooleanField = BooleanField, 
    
    AutoField = AutoField, 
    ForeignKey = ForeignKey,
    -- FileField = FileField,
}