%% Copyright (c) 2016, Loïc Hoguin <essen@ninenines.eu>
%%
%% Permission to use, copy, modify, and/or distribute this software for any
%% purpose with or without fee is hereby granted, provided that the above
%% copyright notice and this permission notice appear in all copies.
%%
%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
%% ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
%% OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

-module(examples_SUITE).
-compile(export_all).

-import(ct_helper, [config/2]).
-import(ct_helper, [doc/1]).
-import(cowboy_test, [gun_open/1]).

%% ct.

all() ->
	ct_helper:all(?MODULE).

%% Remove environment variables inherited from Erlang.mk.
init_per_suite(Config) ->
	os:unsetenv("ERLANG_MK_TMP"),
	os:unsetenv("APPS_DIR"),
	os:unsetenv("DEPS_DIR"),
	os:unsetenv("ERL_LIBS"),
	Config.

end_per_suite(_) ->
	ok.

%% Compile, start and stop releases.

do_get_paths(Example0) ->
	Example = atom_to_list(Example0),
	{ok, CWD} = file:get_cwd(),
	Dir = CWD ++ "/../../examples/" ++ Example,
	Rel = Dir ++ "/_rel/" ++ Example ++ "_example/bin/" ++ Example ++ "_example",
	Log = Dir ++ "/_rel/" ++ Example ++ "_example/log/erlang.log.1",
	{Dir, Rel, Log}.

do_compile_and_start(Example) ->
	{Dir, Rel, _} = do_get_paths(Example),
	%% TERM=dumb disables relx coloring.
	ct:log("~s~n", [os:cmd("cd " ++ Dir ++ " && make distclean && TERM=dumb make all")]),
	ct:log("~s~n", [os:cmd(Rel ++ " stop")]),
	ct:log("~s~n", [os:cmd(Rel ++ " start")]),
	timer:sleep(2000),
	ok.

do_stop(Example) ->
	{_, Rel, Log} = do_get_paths(Example),
	ct:log("~s~n", [os:cmd(Rel ++ " stop")]),
	ct:log("~s~n", [element(2, file:read_file(Log))]),
	ok.

%% Fetch a response.

do_get(Transport, Protocol, Path, Config) ->
	do_get(Transport, Protocol, Path, [], Config).

do_get(Transport, Protocol, Path, ReqHeaders, Config) ->
	Port = case Transport of
		tcp -> 8080;
		ssl -> 8443
	end,
	ConnPid = gun_open([{port, Port}, {type, Transport}, {protocol, Protocol}|Config]),
	Ref = gun:get(ConnPid, Path, ReqHeaders),
	case gun:await(ConnPid, Ref) of
		{response, nofin, Status, RespHeaders} ->
			{ok, Body} = gun:await_body(ConnPid, Ref),
			{Status, RespHeaders, Body};
		{response, fin, Status, RespHeaders} ->
			{Status, RespHeaders, <<>>}
	end.

%% TCP and SSL Hello World.

hello_world(Config) ->
	doc("Hello World example."),
	try
		do_compile_and_start(hello_world),
		do_hello_world(tcp, http, Config),
		do_hello_world(tcp, http2, Config)
	after
		do_stop(hello_world)
	end.

ssl_hello_world(Config) ->
	doc("SSL Hello World example."),
	try
		do_compile_and_start(ssl_hello_world),
		do_hello_world(ssl, http, Config),
		do_hello_world(ssl, http2, Config)
	after
		do_stop(ssl_hello_world)
	end.

do_hello_world(Transport, Protocol, Config) ->
	{200, _, <<"Hello world!">>} = do_get(Transport, Protocol, "/", Config),
	ok.

%% Chunked Hello World.

chunked_hello_world(Config) ->
	doc("Chunked Hello World example."),
	try
		do_compile_and_start(chunked_hello_world),
		do_chunked_hello_world(tcp, http, Config),
		do_chunked_hello_world(tcp, http2, Config)
	after
		do_stop(chunked_hello_world)
	end.

do_chunked_hello_world(Transport, Protocol, Config) ->
	ConnPid = gun_open([{port, 8080}, {type, Transport}, {protocol, Protocol}|Config]),
	Ref = gun:get(ConnPid, "/"),
	{response, nofin, 200, _} = gun:await(ConnPid, Ref),
	%% We expect to receive a chunk every second, three total.
	{data, nofin, <<"Hello\r\n">>} = gun:await(ConnPid, Ref, 2000),
	{data, nofin, <<"World\r\n">>} = gun:await(ConnPid, Ref, 2000),
	{data, IsFin, <<"Chunked!\r\n">>} = gun:await(ConnPid, Ref, 2000),
	%% We may get an extra empty chunk (last chunk for HTTP/1.1,
	%% empty DATA frame with the FIN bit set for HTTP/2).
	case IsFin of
		fin -> ok;
		nofin ->
			{data, fin, <<>>} = gun:await(ConnPid, Ref, 500),
			ok
	end.

%% Cookie.

cookie(Config) ->
	doc("Cookie example."),
	try
		do_compile_and_start(cookie),
		do_cookie(tcp, http, Config),
		do_cookie(tcp, http2, Config)
	after
		do_stop(cookie)
	end.

do_cookie(Transport, Protocol, Config) ->
	{200, _, One} = do_get(Transport, Protocol, "/", Config),
	{200, _, Two} = do_get(Transport, Protocol, "/", [{<<"cookie">>, <<"server=abcdef">>}], Config),
	true = One =/= Two,
	ok.

%% Echo GET.

echo_get(Config) ->
	doc("GET parameter echo example."),
	try
		do_compile_and_start(echo_get),
		do_echo_get(tcp, http, Config),
		do_echo_get(tcp, http2, Config)
	after
		do_stop(echo_get)
	end.

do_echo_get(Transport, Protocol, Config) ->
	{200, _, <<"this is fun">>} = do_get(Transport, Protocol, "/?echo=this+is+fun", Config),
	ok.

%% Echo POST.

echo_post(Config) ->
	doc("POST parameter echo example."),
	try
		do_compile_and_start(echo_post),
		do_echo_post(tcp, http, Config),
		do_echo_post(tcp, http2, Config)
	after
		do_stop(echo_post)
	end.

do_echo_post(Transport, Protocol, Config) ->
	ConnPid = gun_open([{port, 8080}, {type, Transport}, {protocol, Protocol}|Config]),
	Ref = gun:post(ConnPid, "/", [
		{<<"content-type">>, <<"application/octet-stream">>}
	], <<"echo=this+is+fun">>),
	{response, nofin, 200, _} = gun:await(ConnPid, Ref),
	{ok, <<"this is fun">>} = gun:await_body(ConnPid, Ref),
	ok.

%% Eventsource.

eventsource(Config) ->
	doc("Eventsource example."),
	try
		do_compile_and_start(eventsource),
		do_eventsource(tcp, http, Config),
		do_eventsource(tcp, http2, Config)
	after
		do_stop(eventsource)
	end.

do_eventsource(Transport, Protocol, Config) ->
	ConnPid = gun_open([{port, 8080}, {type, Transport}, {protocol, Protocol}|Config]),
	Ref = gun:get(ConnPid, "/eventsource"),
	{response, nofin, 200, Headers} = gun:await(ConnPid, Ref),
	{_, <<"text/event-stream">>} = lists:keyfind(<<"content-type">>, 1, Headers),
	%% Receive a few events.
	{data, nofin, << "id: ", _/bits >>} = gun:await(ConnPid, Ref, 2000),
	{data, nofin, << "id: ", _/bits >>} = gun:await(ConnPid, Ref, 2000),
	{data, nofin, << "id: ", _/bits >>} = gun:await(ConnPid, Ref, 2000),
	gun:close(ConnPid).

%% REST Hello World.

rest_hello_world(Config) ->
	doc("REST Hello World example."),
	try
		do_compile_and_start(rest_hello_world),
		do_rest_hello_world(tcp, http, Config),
		do_rest_hello_world(tcp, http2, Config)
	after
		do_stop(rest_hello_world)
	end.

do_rest_hello_world(Transport, Protocol, Config) ->
	<< "<html>", _/bits >> = do_rest_get(Transport, Protocol,
		"/", undefined, undefined, Config),
	<< "REST Hello World as text!" >> = do_rest_get(Transport, Protocol,
		"/", <<"text/plain">>, undefined, Config),
	<< "{\"rest\": \"Hello World!\"}" >> = do_rest_get(Transport, Protocol,
		"/", <<"application/json">>, undefined, Config),
	not_acceptable = do_rest_get(Transport, Protocol,
		"/", <<"text/css">>, undefined, Config),
	ok.

do_rest_get(Transport, Protocol, Path, Accept, Auth, Config) ->
	ReqHeaders0 = case Accept of
		undefined -> [];
		_ -> [{<<"accept">>, Accept}]
	end,
	ReqHeaders = case Auth of
		undefined -> ReqHeaders0;
		_ -> [{<<"authorization">>, [<<"Basic ">>, base64:encode(Auth)]}|ReqHeaders0]
	end,
	case do_get(Transport, Protocol, Path, ReqHeaders, Config) of
		{200, RespHeaders, Body} ->
			Accept = case Accept of
				undefined -> undefined;
				_ ->
					{_, ContentType} = lists:keyfind(<<"content-type">>, 1, RespHeaders),
					ContentType
			end,
			Body;
		{401, _, _} ->
			unauthorized;
		{406, _, _} ->
			not_acceptable
	end.

%% REST basic auth.

rest_basic_auth(Config) ->
	doc("REST basic authorization example."),
	try
		do_compile_and_start(rest_basic_auth),
		do_rest_basic_auth(tcp, http, Config),
		do_rest_basic_auth(tcp, http2, Config)
	after
		do_stop(rest_basic_auth)
	end.

do_rest_basic_auth(Transport, Protocol, Config) ->
	unauthorized = do_rest_get(Transport, Protocol, "/", undefined, undefined, Config),
	<<"Hello, Alladin!\n">> = do_rest_get(Transport, Protocol, "/", undefined, "Alladin:open sesame", Config),
	ok.

%% File server.

file_server(Config) ->
	doc("File server example with directory listing."),
	try
		do_compile_and_start(file_server),
		do_file_server(tcp, http, Config),
		do_file_server(tcp, http2, Config)
	after
		do_stop(file_server)
	end.

do_file_server(Transport, Protocol, Config) ->
	%% Directory.
	{200, DirHeaders, <<"<!DOCTYPE html><html>", _/bits >>} = do_get(Transport, Protocol, "/", Config),
	{_, <<"text/html">>} = lists:keyfind(<<"content-type">>, 1, DirHeaders),
	_ = do_rest_get(Transport, Protocol, "/", <<"application/json">>, undefined, Config),
	%% Files.
	{200, _, _} = do_get(Transport, Protocol, "/small.mp4", Config),
	{200, _, _} = do_get(Transport, Protocol, "/small.ogv", Config),
	{200, _, _} = do_get(Transport, Protocol, "/test.txt", Config),
	{200, _, _} = do_get(Transport, Protocol, "/video.html", Config),
	ok.

%% Markdown middleware.

markdown_middleware(Config) ->
	doc("Markdown middleware example."),
	try
		do_compile_and_start(markdown_middleware),
		do_markdown_middleware(tcp, http, Config),
		do_markdown_middleware(tcp, http2, Config)
	after
		do_stop(markdown_middleware)
	end.

do_markdown_middleware(Transport, Protocol, Config) ->
	{200, Headers, <<"<h1>", _/bits >>} = do_get(Transport, Protocol, "/video.html", Config),
	{_, <<"text/html">>} = lists:keyfind(<<"content-type">>, 1, Headers),
	ok.

%% Websocket.

websocket(_) ->
	doc("Websocket example."),
	try
		do_compile_and_start(websocket),
		%% We can only initiate a Websocket connection from HTTP/1.1.
		{ok, Pid} = gun:open("127.0.0.1", 8080, #{protocols => [http], retry => 0}),
		{ok, http} = gun:await_up(Pid),
		_ = monitor(process, Pid),
		gun:ws_upgrade(Pid, "/websocket", [], #{compress => true}),
		receive
			{gun_ws_upgrade, Pid, ok, _} ->
				ok;
			Msg1 ->
				exit({connection_failed, Msg1})
		end,
		gun:ws_send(Pid, {text, <<"hello">>}),
		receive
			{gun_ws, Pid, {text, <<"That's what she said! hello">>}} ->
				ok;
			Msg2 ->
				exit({receive_failed, Msg2})
		end,
		gun:ws_send(Pid, close)
	after
		do_stop(websocket)
	end.
