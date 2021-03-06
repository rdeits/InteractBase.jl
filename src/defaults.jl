for op in [:filepicker, :datepicker, :colorpicker, :timepicker, :spinbox,
           :autocomplete, :input, :dropdown, :checkbox, :toggle, :togglecontent,
           :textbox, :textarea, :button, :slider, :entry,
           :radiobuttons, :checkboxes, :toggles, :togglebuttons, :tabs, :tabulator,
           :wrap, :wrapfield, :wdglabel,
           :manipulateinnercontainer, :manipulateoutercontainer,
           :getclass]
    @eval begin
        function $op(args...; kwargs...)
            length(args) > 0 && args[1] isa WidgetTheme &&
                error("Function " * string($op) * " was about to overflow: check the signature")
            $op(gettheme(), args...; kwargs...)
        end

        widget(::Val{$(Expr(:quote, op))}, args...; kwargs...) = $op(args...; kwargs...)
    end
end

div(args...; kwargs...) = Node(:div, args...; kwargs...)

node(args...; kwargs...) = Node(args...; kwargs...)
node(s::AbstractString, args...; kwargs...) = node(Symbol(s), args...; kwargs...)
