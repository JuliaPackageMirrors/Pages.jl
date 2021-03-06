"""
Broadcast a message to all connected web pages to be interpetted by WebSocket listener. For example, in JavaScript:

var sock = new WebSocket('ws://'+window.location.host);
sock.onmessage = function( message ){
    var msg = JSON.parse(message.data);
    console.log(msg);
}
"""
function broadcast(msg::Dict)
    for (sid,s) in sessions
        c = s.client
        if ~c.is_closed
            write(c, json(msg))
        end
    end
end
broadcast(t,msg) = broadcast(Dict("type"=>t,"data"=>msg))

"""
Send a message to the specified connection to be interpetted by WebSocket listener. For example, in JavaScript:

var sock = new WebSocket('ws://'+window.location.host);
sock.onmessage = function( message ){
    var msg = JSON.parse(message.data);
    console.log(msg);
}
"""
function message(client::WebSocket,msg::Dict)
    if ~client.is_closed
        write(client, json(msg))
    end
end
message(client::WebSocket,t,msg) = message(client,Dict("type"=>t,"data"=>msg))
function message(id::Int,t,msg)
    for (sid,s) in sessions
        if isequal(id,s.client.id)
            message(s.client,Dict("type"=>t,"data"=>msg))
        end
    end
end

"""
Block Julia control flow until until callback["notify"](name) is called.
"""
function block(f::Function,name)
    conditions[name] = Condition()
    f()
    wait(conditions[name])
    delete!(conditions,name)
end

"""Add a JS library to the current page from a url."""
function add_library(url)
    name = basename(url)
    block(name) do
        broadcast("script","""
            var script = document.createElement("script");
            script.src = "$(url)";
            script.onload = Pages.notify("$(name)");
            document.head.appendChild(script);
        """)
    end
end

type Element
    id::String
    tag::String
    name::String
    attr::Dict{String,String}
    style::Dict{String,String}
    html::String
    text::String
    parent::String

    function Element(;id = "",tag = "div",name = "element",attr = Dict{String,String}(),style = Dict{String,String}(),html = "",text = "",parent = "body")
        new(id,tag,name,attr,style,html,text,parent)
    end
end

function assign(io::IO,element::Element)
    # ==========================================================================
    # Add attributes to element
    for prop in ["attr","style"]
        field = getfield(element,Symbol(prop))
        for key in keys(field)
            print(io,"""
                $(element.name).$(prop)("$(key)","$(field[key])");
            """)
        end
    end
    # ==========================================================================
    # Add html & text to element
    for prop in ["html","text"]
        field = getfield(element,Symbol(prop))
        if !isempty(field)
            print(io,"""
                $(element.name).$(prop)("$(field)");
            """)
        end
    end
    takebuf_string(io)
end

function add(io::IO,element::Element)
    # ==========================================================================
    # Get or create element
    print(io,"""
        var parent = d3.select("$(element.parent)")
        var $(element.name) = null;
    """)
    if !isempty(element.id)
        print(io,"""
            var check = document.getElementById("$(element.id)");
            if (check === null) {
                $(element.name) = parent.append("$(element.tag)").attr("id","$(element.id)");
            } else {
                $(element.name) = d3.select("#$(element.id)");
            };
        """)
    else
        print(io,"""
            $(element.name) = d3.select("$(element.parent)").append("$(element.tag)");
        """)
    end
    print(io,assign(io,element))
    takebuf_string(io)
end
function add(element::Element)
    Pages.broadcast("script",add(IOBuffer(),element))
end

function append(io::IO,element::Element;parent = """d3.select("body")""")
    if isempty(element.name)
        print(io,"""
            $(parent).append("$(element.tag)");
        """)
    else
        print(io,"""
            $(element.name) = $(parent).append("$(element.tag)");
        """)
    end
    print(io,assign(io,element))
    takebuf_string(io)
end

function remove(io::IO,tag;parent = """d3.select("body")""")
    print(io,"""
        $(parent).selectAll("$(tag)").remove();
    """)
    takebuf_string(io)
end
function remove(tag;parent = """d3.select("body")""")
    Pages.broadcast("script",remove(IOBuffer(),tag,parent=parent))
end

function add_select(io::IO,options,element::Element)
    element.tag == "select" || error("Element must have tag = select.")
    print(io,add(io,element))
    print(io,remove(io,"option",parent=element.name))
    # print(io,"""
    #     $(element.name).selectAll("option").remove();
    # """)
    for key in keys(options)
        print(io,"""
            $(element.name).append("option").attr("value","$(key)").text("$(options[key])");
        """)
    end
    takebuf_string(io)
end
function add_select(options,element::Element)
    Pages.broadcast("script",add_select(IOBuffer(),options,element))
end

function add_table(io::IO,df::DataFrame;table = Element(tag="table",name="table"),tr = Element(tag="tr",name="row"),th = Element(tag="th",name="header"),td = Element(tag="td",name="cell"))
    table.tag == "table" || error("Element must have tag = table.")
    tr.tag == "tr" || error("Element must have tag = tr.")
    th.tag == "th" || error("Element must have tag = th.")
    td.tag == "td" || error("Element must have tag = td.")
    print(io,add(io,table))
    print(io,remove(io,"tr",parent=table.name))
    # ==========================================================================
    # Add header
    print(io,"""
        var $(tr.name) = null;
    """)
    print(io,append(io,tr,parent=table.name))
    print(io,"""
        var $(th.name) = null;
    """)
    for name in names(df)
        th.html = string(name)
        print(io,append(io,th,parent=tr.name))
    end
    # ==========================================================================
    # Add data
    print(io,"""
        var $(td.name) = null;
    """)
    for irow in 1:size(df,1)
        row = df[irow,:]
        print(io,append(io,tr,parent=table.name))
        for name in names(df)
            td.html = string(row[name][1])
            print(io,append(io,td,parent=tr.name))
        end
    end
    takebuf_string(io)
end
function add_table(df::DataFrame;table = Element(tag="table",name="table"),tr = Element(tag="tr",name="row"),th = Element(tag="th",name="header"),td = Element(tag="td",name="cell"))
    Pages.broadcast("script",add_table(IOBuffer(),df,table=table,tr=tr,th=th,td=td))
end
