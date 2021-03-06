"""
`filepicker(label="Choose a file..."; multiple=false, accept="*")`

Create a widget to select files.
If `multiple=true` the observable will hold an array containing the paths of all
selected files. Use `accept` to only accept some formats, e.g. `accept=".csv"`
"""
function filepicker(::WidgetTheme, lbl="Choose a file..."; attributes=PropDict(),
    label=lbl, className="", value = nothing, multiple=false, kwargs...)

    (value isa Observable) || (value = Observable{Any}(value))
    if multiple
        onFileUpload = js"""function (data, e){
            var files = e.target.files;
            var fileArray = Array.from(files);
            this.filename(fileArray.map(function (el) {return el.name;}));
            return this.path(fileArray.map(function (el) {return el.path;}));
        }
        """
        if value[] == nothing
            path, filename = Observable.((String[],String[]))
        else
            path = value
            filename = Observable(basename.(value[]))
        end
    else
        onFileUpload = js"""function(data, e) {
            var files = e.target.files;
            this.filename(files[0].name);
            return this.path(files[0].path);
        }
        """
        if value[] == nothing
            path, filename = Observable.(("",""))
        else
            path = value
            filename = Observable(basename(value[]))
        end
    end
    multiple && (attributes=merge(attributes, PropDict(:multiple => true)))
    attributes = merge(attributes, PropDict(:type => "file", :style => "display: none;",
        Symbol("data-bind") => "event: {change: onFileUpload}"))
    className = mergeclasses(getclass(:input, "file"), className)
    template = dom"div[style=display:flex; align-items:center;]"(
        Node(:label, className=getclass(:input, "file", "label"))(
            Node(:input; className=className, attributes=attributes, kwargs...),
            Node(:span,
                Node(:span, (Node(:i, className = getclass(:input, "file", "icon"))), className=getclass(:input, "file", "span", "icon")),
                Node(:span, label, className=getclass(:input, "file", "span", "label")),
                className=getclass(:input, "file", "span"))
        ),
        Node(:span, attributes = Dict("data-bind" => " text: filename() == '' ? 'No file chosen' : filename()"),
            className = getclass(:input, "file", "name"))
    )

    observs = ["path" => path, "filename" => filename]
    ui = knockout(template, observs, methods = ["onFileUpload" => onFileUpload])
    slap_design!(ui)
    Widget{:filepicker}(observs, scope = ui, output = ui["path"], layout = t -> dom"div.field"(t.scope))
end

_parse(::Type{S}, x) where{S} = parse(S, x)
function _parse(::Type{Dates.Time}, x)
    h, m = parse.(Int, split(x, ':'))
    Dates.Time(h, m)
end

"""
`datepicker(value::Union{Dates.Date, Observable, Void}=nothing)`

Create a widget to select dates.
"""
function datepicker end

"""
`timepicker(value::Union{Dates.Time, Observable, Void}=nothing)`

Create a widget to select times.
"""
function timepicker end

for (func, typ, str) in [(:timepicker, :(Dates.Time), "time"), (:datepicker, :(Dates.Date), "date") ]
    @eval begin
        function $func(::WidgetTheme, val=nothing; value=val, kwargs...)
            (value isa Observable) || (value = Observable{Union{$typ, Void}}(value))
            f = x -> x === nothing ? "" : split(string(x), '.')[1]
            g = t -> _parse($typ, t)
            pair = ObservablePair(value, f=f, g=g)
            ui = input(pair.second; typ=$str, kwargs...)
            Widget{$(Expr(:quote, func))}(ui, output = value)
        end
    end
end

"""
`colorpicker(value::Union{Color, Observable}=colorant"#000000")`

Create a widget to select colors.
"""
function colorpicker(::WidgetTheme, val=colorant"#000000"; value=val, kwargs...)
    (value isa Observable) || (value = Observable{Color}(value))
    f = t -> "#"*hex(t)
    g = t -> parse(Colorant,t)
    pair = ObservablePair(value, f=f, g=g)
    ui = input(pair.second; typ="color", kwargs...)
    Widget{:colorpicker}(ui, output = value)
end

"""
`spinbox([range,] label=""; value=nothing)`

Create a widget to select numbers with placeholder `label`. An optional `range` first argument
specifies maximum and minimum value accepted as well as the step.
"""
function spinbox(::WidgetTheme, label=""; value=nothing, placeholder=label, isinteger=isa(_val(value), Integer), kwargs...)
    T = isinteger ? Int : Float64
    (value isa Observable) || (value = Observable{Union{T, Void}}(value))
    ui = input(value; isnumeric=true, placeholder=placeholder, typ="number", kwargs...)
    Widget{:spinbox}(ui, output = value)
end

spinbox(T::WidgetTheme, vals::Range, args...; value=first(vals), isinteger=(eltype(vals) <: Integer), kwargs...) =
    spinbox(T, args...; value=value, isinteger=isinteger, min=minimum(vals), max=maximum(vals), step=step(vals), kwargs...)

"""
`autocomplete(options, label=""; value="")`

Create a textbox input with autocomplete options specified by `options`, with `value`
as initial value and `label` as label.
"""
function autocomplete(::WidgetTheme, options, args...; attributes=PropDict(), kwargs...)
    (options isa Observable) || (options = Observable{Any}(options))
    option_array = _js_array(options)
    s = gensym()
    attributes = merge(attributes, PropDict(:list => s))
    t = textbox(args...; extra_obs=["options_js" => option_array], attributes=attributes, kwargs...)
    scope(t).dom = Node(:div,
        scope(t).dom,
        Node(:datalist, Node(:option, attributes=Dict("data-bind"=>"value : key"));
            attributes = Dict("data-bind" => "foreach : options_js", "id" => s))
    )
    w = Widget{:autocomplete}(t)
    w.children[:options] = options
    w
end

"""
`input(o; typ="text")`

Create an HTML5 input element of type `type` (e.g. "text", "color", "number", "date") with `o`
as initial value.
"""
function input(::WidgetTheme, o; extra_js=js"", extra_obs=[], label=nothing, typ="text", wdgtyp=typ,
    className="", style=Dict(), internalvalue=nothing, isnumeric=Knockout.isnumeric(o),
    displayfunction=js"function (){return this.value();}", attributes=Dict(), bind="value", valueUpdate="input", kwargs...)

    (o isa Observable) || (o = Observable(o))
    isnumeric && (bind == "value") && (bind = "numericValue")
    bindto = (internalvalue == nothing) ? "value" : "internalvalue"
    data = Pair{String, Observable}["changes" => Observable(0), "value" => o]
    (internalvalue !== nothing) && push!(data, "internalvalue" => internalvalue)
    append!(data, (string(key) => val for (key, val) in extra_obs))
    attrDict = merge(
        attributes,
        Dict(:type => typ, Symbol("data-bind") => "$bind: $bindto, valueUpdate: '$valueUpdate', event: {change : function () {this.changes(this.changes()+1)}}")
    )
    className = mergeclasses(getclass(:input, wdgtyp), className)
    template = Node(:input; className=className, attributes=attrDict, style=style, kwargs...)()
    ui = knockout(template, data, extra_js, computed = ["displayedvalue" => displayfunction])
    (label != nothing) && (scope(ui).dom = flex_row(wdglabel(label), scope(ui).dom))
    slap_design!(ui)
    Widget{:input}(data, scope = ui, output = ui["value"], layout = t -> dom"div.field"(t.scope))
end

function input(::WidgetTheme; typ="text", kwargs...)
    if typ in ["checkbox", "radio"]
        o = false
    elseif typ in ["number", "range"]
        o = 0.0
    else
        o = ""
    end
    input(o; typ=typ, kwargs...)
end

"""
`button(content... = "Press me!"; value=0)`

A button. `content` goes inside the button.
Note the button `content` supports a special `clicks` variable, that gets incremented by `1`
with each click e.g.: `button("clicked {{clicks}} times")`.
The `clicks` variable is initialized at `value=0`
"""
function button(::WidgetTheme, content...; label = "Press me!", value = 0, style = Dict{String, Any}(),
    className = getclass(:button, "primary"), attributes=Dict(), kwargs...)

    isempty(content) && (content = (label,))
    (value isa Observable) || (value = Observable(value))
    className = mergeclasses(getclass(:button), className)
    attrdict = merge(
        Dict("data-bind"=>"click : function () {this.clicks(this.clicks()+1)}"),
        attributes
    )
    template = Node(:button, content...; className=className, attributes=attrdict, style=style, kwargs...)
    button = knockout(template, ["clicks" => value])
    slap_design!(button)
    Widget{:button}(scope = button, output = value, layout = t -> dom"div.field"(t.scope))
end

for wdg in [:toggle, :checkbox]
    @eval begin
        $wdg(::WidgetTheme, value, lbl::AbstractString=""; label=lbl, kwargs...) =
            $wdg(gettheme(); value=value, label=label, kwargs...)

        $wdg(::WidgetTheme, label::AbstractString, val=false; value=val, kwargs...) =
            $wdg(gettheme(); value=value, label=label, kwargs...)

        $wdg(::WidgetTheme, value::AbstractString, label::AbstractString; kwargs...) =
            error("value cannot be a string")

        function $wdg(::WidgetTheme; bind="checked", valueUpdate="change", value=false, label="", labelclass="", kwargs...)
            s = gensym() |> string
            (label isa Tuple) || (label = (label,))
            widgettype = $(Expr(:quote, wdg))
            wdgtyp = string(widgettype)
            labelclass = mergeclasses(getclass(:input, wdgtyp, "label"), labelclass)
            ui = input(value; bind=bind, typ="checkbox", valueUpdate="change", wdgtyp=wdgtyp, id=s, kwargs...)
            scope(ui).dom = dom"div.field"(scope(ui).dom, dom"label[className=$labelclass, for=$s]"(label...))
            Widget{widgettype}(ui)
        end
    end
end

"""
`checkbox(value::Union{Bool, Observable}=false; label)`

A checkbox.
e.g. `checkbox(label="be my friend?")`
"""
function checkbox end

"""
`toggle(value::Union{Bool, Observable}=false; label)`

A toggle switch.
e.g. `toggle(label="be my friend?")`
"""
function toggle end

"""
`togglecontent(content, value::Union{Bool, Observable}=false; label)`

A toggle switch that, when activated, displays `content`
e.g. `togglecontent(checkbox("Yes, I am sure"), false, label="Are you sure?")`
"""
function togglecontent(::WidgetTheme, content, args...; vskip = 0em, kwargs...)
    btn = toggle(gettheme(), args...; kwargs...)
    scope(btn).dom =  vbox(
        scope(btn).dom,
        Node(:div,
            content,
            attributes = Dict("data-bind" => "visible: value")
        )
    )
    Widget{:togglecontent}(btn)
end

"""
`textbox(hint=""; value="")`

Create a text input area with an optional placeholder `hint`
e.g. `textbox("enter number:")`. Use `typ=...` to specify the type of text. For example
`typ="email"` or `typ=password`. Use `multiline=true` to display a `textarea` spanning
several lines.
"""
function textbox(::WidgetTheme, hint=""; multiline=false, placeholder=hint, value="", typ="text", kwargs...)
    multiline && return textarea(gettheme(); placeholder=placeholder, value=value, kwargs...)
    Widget{:textbox}(input(value; typ=typ, placeholder=placeholder, kwargs...))
end

"""
`textarea(hint=""; value="")`

Create a textarea with an optional placeholder `hint`
e.g. `textarea("enter number:")`. Use `rows=...` to specify how many rows to display
"""
function textarea(::WidgetTheme, hint=""; label=nothing, className="",
    placeholder=hint, value="", attributes=Dict(), style=Dict(), bind="value", valueUpdate = "input", kwargs...)

    (value isa Observable) || (value = Observable(value))
    attrdict = convert(PropDict, attributes)
    attrdict[:placeholder] = placeholder
    attrdict["data-bind"] = "$bind: value, valueUpdate: '$valueUpdate'"
    className = mergeclasses(getclass(:textarea), className)
    template = Node(:textarea; className=className, attributes=attrdict, style=style, kwargs...)
    ui = knockout(template, ["value" => value])
    (label != nothing) && (scope(ui).dom = flex_row(wdglabel(label), scope(ui).dom))
    slap_design!(ui)
    Widget{:textarea}(scope = ui, output = ui["value"], layout = t -> dom"div.field"(t.scope))
end

"""
```
function slider(vals::Range; # Range
                value=medianelement(valse),
                label="", kwargs...)
```

Creates a slider widget which can take on the values in `vals`, and updates
observable `value` when the slider is changed:
"""
function slider(::WidgetTheme, vals::Range;
    className=getclass(:input, "range", "fullwidth"),
    isinteger=(eltype(vals) <: Integer), showvalue=true,
    label=nothing, value=medianelement(vals), precision=6, kwargs...)

    (value isa Observable) || (value = convert(eltype(vals), value))
    displayfunction = isinteger ? js"function () {return this.value();}" :
                                  js"function () {return this.value().toPrecision($precision);}"
    ui = input(value; displayfunction=displayfunction,
        typ="range", min=minimum(vals), max=maximum(vals), step=step(vals), className=className, kwargs...)
    if (label != nothing) || showvalue
        scope(ui).dom = showvalue ?  flex_row(wdglabel(label), scope(ui).dom, Node(:p, attributes = Dict("data-bind" => "text: displayedvalue"))):
                                     flex_row(wdglabel(label), scope(ui).dom)
    end
    Widget{:slider}(ui)
end

function slider(::WidgetTheme, vals::AbstractVector; value=medianelement(vals), kwargs...)
    (value isa Observable) || (value = Observable{eltype(vals)}(value))
    (vals isa Array) || (vals = collect(vals))
    idxs::Range = 1:(length(vals))
    idx = Observable(findfirst(t -> t == value[], vals))
    extra_js = js"""
    this.values = JSON.parse($(JSON.json(vals)))
    this.internalvalue.subscribe(function (value){
        this.value(this.values[value-1]);
    }, this)
    this.value.subscribe(function (value){
        var index = this.values.indexOf(value);
        this.internalvalue(index+1);
    }, this)
    """
    slider(idxs; extra_js=extra_js, value=value, internalvalue=idx, isinteger=(eltype(vals) <: Integer), kwargs...)
end

function wdglabel(T::WidgetTheme, text; padt=5, padr=10, padb=0, padl=10,
    className="", style = Dict(), kwargs...)

    className = mergeclasses(getclass(:wdglabel), className)
    padding = Dict(:padding=>"$(padt)px $(padr)px $(padb)px $(padl)px")
    Node(:label, text; className=className, style = merge(padding, style), kwargs...)
end

function flex_row(a,b,c=dom"div"())
    dom"div.[style=display:flex; justify-content:center; align-items:center;]"(
        dom"div[style=text-align:right;width:18%]"(a),
        dom"div[style=flex-grow:1; margin: 0 2%]"(b),
        dom"div[style=width:18%]"(c)
    )
end

flex_row(a) =
    dom"div.[style=display:flex; justify-content:center; align-items:center;]"(a)
