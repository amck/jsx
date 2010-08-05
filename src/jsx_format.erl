%% The MIT License

%% Copyright (c) 2010 Alisdair Sullivan <alisdairsullivan@yahoo.ca>

%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:

%% The above copyright notice and this permission notice shall be included in
%% all copies or substantial portions of the Software.

%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%% THE SOFTWARE.


-module(jsx_format).
-author("alisdairsullivan@yahoo.ca").

-export([format/2]).

-include("./include/jsx_types.hrl").



-record(opts, {
    space = 0,
    indent = 0,
    output_encoding = iolist,
    strict = true
}).



-define(newline, $\n).
-define(space, 16#20).  %% ascii code for space
-define(quote, $\").
-define(comma, $,).
-define(colon, $:).
-define(start_object, ${).
-define(end_object, $}).
-define(start_array, $[).
-define(end_array, $]).



-spec format(JSON::binary(), Opts::format_opts()) -> binary() | iolist().
    
format(JSON, Opts) when is_binary(JSON) ->
    P = jsx:parser(extract_parser_opts(Opts)),
    format(fun() -> P(JSON) end, Opts);
    
format(F, OptsList) when is_function(F) ->
    Opts = parse_opts(OptsList, #opts{}),
    {Continue, String} = format_something(F(), Opts, 0),
    case Continue() of
        {event, end_json, _} -> encode(String, Opts)
        ; _ -> {error, badarg}
    end.


parse_opts([{indent, Val}|Rest], Opts) ->
    parse_opts(Rest, Opts#opts{indent = Val});
parse_opts([indent|Rest], Opts) ->
    parse_opts(Rest, Opts#opts{indent = 1});
parse_opts([{space, Val}|Rest], Opts) ->
    parse_opts(Rest, Opts#opts{space = Val});
parse_opts([space|Rest], Opts) ->
    parse_opts(Rest, Opts#opts{space = 1});
parse_opts([{output_encoding, Val}|Rest], Opts) ->
    parse_opts(Rest, Opts#opts{output_encoding = Val});
parse_opts([], Opts) ->
    Opts.


extract_parser_opts(Opts) ->
    [ {K, V} || {K, V} <- Opts, lists:member(K, [comments, encoding]) ].
    

format_something({event, start_object, Next}, Opts, Level) ->
    {Continue, Object} = format_object(Next(), [], Opts, Level + 1),
    {Continue, [?start_object, Object, ?end_object]};
format_something({event, start_array, Next}, Opts, Level) ->
    {Continue, Array} = format_array(Next(), [], Opts, Level + 1),
    {Continue, [?start_array, Array, ?end_array]};
format_something({event, {Type, Value}, Next}, _Opts, _Level) ->
    {Next, [encode(Type, Value)]}.
    
    
format_object({event, end_object, Next}, Acc, _Opts, _Level) ->
    {Next, Acc};
format_object({event, {key, Key}, Next}, Acc, Opts, Level) ->
    {Continue, Value} = format_something(Next(), Opts, Level),
    case Continue() of
        {event, end_object, NextNext} -> 
            {NextNext, [Acc, indent(Opts, Level), encode(string, Key), ?colon, space(Opts), Value]}
        ; Else -> 
            format_object(Else, 
                [Acc, indent(Opts, Level), encode(string, Key), ?colon, space(Opts), Value, ?comma], 
                Opts, 
                Level
            )
    end.
    
format_array({event, end_array, Next}, Acc, _Opts, _Level) ->
    {Next, Acc};
format_array(Event, Acc, Opts, Level) ->
    {Continue, Value} = format_something(Event, Opts, Level),
    case Continue() of
        {event, end_array, NextNext} ->
            {NextNext, [Acc, indent(Opts, Level), Value]}
        ; Else ->
            format_array(Else, [Acc, indent(Opts, Level), Value, ?comma], Opts, Level)
    end.


-define(is_utf_encoding(X),
    X == utf8; X == utf16; X == utf32; X == {utf16, little}; X == {utf32, little}
).

encode(Acc, Opts) when is_list(Acc) ->
    case Opts#opts.output_encoding of
        iolist -> Acc
        ; UTF when ?is_utf_encoding(UTF) -> unicode:characters_to_binary(Acc, utf8, UTF)
        ; _ -> erlang:throw(badarg)
    end;
encode(string, String) ->
    [?quote, String, ?quote];
encode(literal, Literal) ->
    erlang:atom_to_list(Literal);
encode(_, Number) ->
    Number.


indent(Opts, Level) ->
    case Opts#opts.indent of
        0 -> []
        ; X when X > 0 ->
            Indent = [ ?space || _ <- lists:seq(1, X) ],
            indent(Indent, Level, [?newline])
    end.

indent(_Indent, 0, Acc) ->
    Acc;
indent(Indent, N, Acc) ->
    indent(Indent, N - 1, [Acc, Indent]).
    
    
space(Opts) ->
    case Opts#opts.space of
        0 -> []
        ; X when X > 0 -> [ ?space || _ <- lists:seq(1, X) ]
    end.