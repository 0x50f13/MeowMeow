-module(server).
-export([run/1, run_synchronized/1, start/0, stop/0, start_async/0, abort_init/1]).
-import(socket, [create_socket/1, socket_recv/2, socket_accept/3, socket_send/2, socket_recv_all/2]).
-import(handle, [handle_http11/1, abort/1]).
-import(parse_http, [http2map/1]).
-include_lib("kernel/include/inet.hrl").
-include("config.hrl").

tup2list(Tuple) -> tup2list(Tuple, 1, tuple_size(Tuple)).

tup2list(Tuple, Pos, Size) when Pos =< Size ->
  [element(Pos, Tuple) | tup2list(Tuple, Pos + 1, Size)];
tup2list(_Tuple, _Pos, _Size) -> [].

handle_connection(Sock) ->
  case socket:peername(Sock) of
    {ok, Addr} ->
      logging:debug("Addr = ~p @server.erl:19", [Addr]),
      PidHandler = spawn(fun() -> handle:handler_start(Sock) end),
      spawn(fun() -> io_proxy:io_proxy_tcp_start(Sock, PidHandler) end);
    {error, enotconn} ->
      logging:warn("Unexpected disconnect of a client. Maybe a port scan?");
    {error, Any} ->
      logging:err("Error getting peername: ~p", [Any])
  end.

loop(Sock) ->
  logging:debug("Entered loop"),
  case socket:accept(Sock) of
    {ok, Socket} ->
  	logging:debug("Entering handle"),
  	handle_connection(Socket),
  	loop(Sock);
    Any ->
        logging:err("Accept failed: ~p @ server:loop/1", [Any])
   end.

listen(Port) ->
  Addr = #{addr => util:str2addr(configuration:get("ListenHost",string)), family => inet, port => Port},
  {ok, Sock} = socket:open(inet, stream, tcp),
  case socket:bind(Sock, Addr) of
    {ok, _} ->
      R = socket:sockname(Sock),
      ok = socket:listen(Sock),
      socket:setopt(Sock, socket, reuseaddr, true),
      socket:setopt(Sock, socket, reuseport, true),
      logging:info("Listening on port ~p", [Port]),
      spawn(fun() -> loop(Sock) end),
      R;
    {error, Reason} ->
      logging:err("Failed to bind to ~s:~p. Reason: ~s", [configuration:get("ListenHost",string),Port, Reason]),
      {error, Reason}
  end.

do_listen(Sock,Port) ->
    R = socket:sockname(Sock),
    ok = socket:listen(Sock),
    socket:setopt(Sock, socket, reuseaddr, true),
    socket:setopt(Sock, socket, reuseport, true),
    logging:info("Listening on port ~p", [Port]),
    loop(Sock),
    R.  
listen_synchronized(Port) ->
  %% Does not create new process
  Addr = #{addr => util:str2addr(configuration:get("ListenHost",string)), family => inet, port => Port},
  {ok, Sock} = socket:open(inet, stream, tcp),
  case socket:bind(Sock, Addr) of
    ok ->
      do_listen(Sock, Port);
    {ok, _} ->
      logging:warn("Seems that you use old version of Erlang. This may lead to webserver crash or work incorrectly due to backward incompatability of Erlang!"),
      do_listen(Sock, Port);    
    {error, Reason} ->
      logging:debug("Bind addr=~p",[util:str2addr(configuration:get("ListenHost",string))]),
      logging:err("Failed to bind ~s:~p. Reason: ~s", [configuration:get("ListenHost",string),Port, Reason]),
      {error, Reason}
  end.

run(Port) ->
  configuration:load(),
  rules:init_rules(),
  rules:register_basic(),
  access:load_access(?accessfile),
  listen(Port).

run_synchronized(Port) ->
  listen_synchronized(Port).

start() ->
  io:fwrite("                                                                         
______  ___                    ______  ___                     
___   |/  /_____________      ____   |/  /_____________      __
__  /|_/ /_  _ \\  __ \\_ | /| / /_  /|_/ /_  _ \\  __ \\_ | /| / /
_  /  / / /  __/ /_/ /_ |/ |/ /_  /  / / /  __/ /_/ /_ |/ |/ / 
/_/  /_/  \\___/\\____/____/|__/ /_/  /_/  \\___/\\____/____/|__/  
                                                               
Version ~s~n", [?version]),
  configuration:load(),
  rules:init_rules(),
  rules:register_basic(),
  case access:load_access(?accessfile) of
	  ok -> run_synchronized(configuration:get("ListenPort", int));
	  {error, _} -> logging:err("Refusing to start server due to error while loading access")
  end.

start_async() -> 
   spawn(fun() -> start() end).

stop() ->
  init:stop().

abort_init(Reason) ->
  logging:err("Aborting init: ~p", [Reason]),
  init:stop(255).
