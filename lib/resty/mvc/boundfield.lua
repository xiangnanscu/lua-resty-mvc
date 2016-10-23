local utils = require"resty.mvc.utils"
local to_html_attrs = utils.to_html_attrs
local string_format = string.format
local table_concat = table.concat
local table_insert = table.insert
local UNSET = {}

local BoundField = {}
function BoundField.new(cls, self)
    self = self or {}
    cls.__index = cls
    return setmetatable(self, cls)
end
function BoundField.instance(cls, form, field, name)
    local self = cls:new{form=form, field=field, name=name}
    self.html_name = form:add_prefix(name)
    if not field.label then
        self.label = name
    else
        self.label = field.label
    end
    self.help_text = field.help_text
    self._initial_value = UNSET
    return self
end
function BoundField.errors(self)
    -- """
    -- Returns an ErrorList for this field. Returns an empty ErrorList
    -- if there are none.
    -- """
    return self.form:errors()[self.name]
end
function BoundField.render(self)
    -- just for consistency with api of `field` and `form`
    return self:as_widget()
end
function BoundField.as_widget(self, widget, attrs)
    -- """
    -- Renders the field by rendering the passed widget, adding any HTML
    -- attributes passed as attrs.  If no widget is specified, then the
    -- field's default widget will be used.
    -- """
    if not widget then
        widget = self.field.widget
    end
    attrs = attrs or {}
    if self.field.disabled then
        attrs.disabled = true
    end
    local auto_id = self:auto_id()
    if auto_id and not attrs.id and not widget.attrs.id then
        attrs.id = auto_id
    end
    return widget:render(self.html_name, self:value(), attrs)
end
function BoundField.data(self)
    return self.field.widget:value_from_datadict(self.form.data, self.form.files, self.html_name)
end
function BoundField.value(self)
    -- Returns the value for this BoundField, using the initial value if
    -- the form is not bound or the data otherwise.
    local data;
    if not self.form.is_bound then
        data = self.form.initial[self.name] or self.field.initial
        if type(data) == 'function' then
            if self._initial_value ~= UNSET then
                data = self._initial_value
            else
                data = data()
                self._initial_value = data
            end
        end
    else
        data = self.field:bound_data(
            self:data(), self.form.initial[self.name] or self.field.initial
        )
    end
    -- return data
    return self.field:prepare_value(data) 
end
function BoundField.label_tag(self, contents, attrs, label_suffix)
    -- """
    -- Wraps the given contents in a <label>, if the field has an ID attribute.
    -- contents should be 'mark_safe'd to avoid HTML escaping. If contents
    -- aren't given, uses the field's HTML-escaped label.

    -- If attrs are given, they're used as HTML attributes on the <label> tag.

    -- label_suffix allows overriding the form's label_suffix.
    -- """
    attrs = attrs or {}
    contents = contents or self.label
    if label_suffix == nil then
        local ls = self.field.label_suffix
        if ls ~= nil then
            label_suffix = ls
        else
            label_suffix = self.form.label_suffix
        end
    end
    if label_suffix and contents then
        contents = contents..label_suffix
    end
    local widget = self.field.widget
    local id = widget.attrs.id or self:auto_id()
    if id then
        local id_for_label = widget:id_for_label(id)
        if id_for_label then
            -- ** not make a copy of attrs
            attrs['for'] = id_for_label
        end
        if self.field.required and self.form.required_css_class then
            if attrs.class then
                attrs.class = attrs.class..' '..self.form.required_css_class
            else
                attrs.class = self.form.required_css_class
            end
        end
        if attrs then
            attrs = utils.to_html_attrs(attrs)  
        else 
            attrs = ''
        end
        contents = string_format('<label%s>%s</label>', attrs, contents)
    end
    return contents
end
function BoundField.css_classes(self, extra_classes)
    -- """
    -- Returns a string of space-separated CSS classes for this field.
    -- """
    if type(extra_classes) == 'string' then
        local res = {}
        for e in extra_classes:gmatch("%S+") do
            res[#res+1] = e
        end
        extra_classes = res
    end
    extra_classes = extra_classes or {}
    if self:errors() and self.form.error_css_class then
        extra_classes[#extra_classes+1] = self.form.error_css_class
    end
    if self.field.required and self.form.required_css_class then
        extra_classes[#extra_classes+1] = self.form.required_css_class
    end
    extra_classes[#extra_classes+1] = self.form.field_html_class
    return table_concat(extra_classes, ' ') 
end
function BoundField.is_hidden(self)
    return self.field.widget:is_hidden()
end
function BoundField.auto_id(self)
    -- """
    -- Calculates and returns the ID attribute for this BoundField, if the
    -- associated Form has specified auto_id. Returns an empty string otherwise.
    -- """
    local auto_id = self.form.auto_id
    if auto_id and auto_id:find('%%s') then
        return string_format(auto_id, self.html_name) 
    elseif auto_id then
        return self.html_name
    end
    return ''
end
function BoundField.id_for_label(self)
    -- """
    -- Wrapper around the field widget's `id_for_label` method.
    -- Useful, for example, for focusing on this field regardless of whether
    -- it has a single widget or a MultiWidget.
    -- """
    local widget = self.field.widget
    local id = widget.attrs.id or self.auto_id()
    return widget:id_for_label(id)
end
function BoundField.as_text(self, attrs)
    return self:as_widget(Widget.TextInput(), attrs)
end
function BoundField.as_textarea(self, attrs)
    return self:as_widget(Widget.Textarea(), attrs)
end
function BoundField.as_hidden(self, attrs)
    return self:as_widget(self.field.hidden_widget().TextInput(), attrs)
end

return BoundField