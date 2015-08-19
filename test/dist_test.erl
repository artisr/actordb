% This Source Code Form is subject to the terms of the Mozilla Public
% License, v. 2.0. If a copy of the MPL was not distributed with this
% file, You can obtain one at http://mozilla.org/MPL/2.0/.

% ./detest test/dist_test.erl single
% ./detest test/dist_test.erl cluster

-module(dist_test).
-export([cfg/1,setup/1,cleanup/1,run/1]).
-define(INF(F,Param),io:format("~p ~p:~p ~s~n",[ltime(),?MODULE,?LINE,io_lib:fwrite(F,Param)])).
-define(INF(F),?INF(F,[])).
-define(NUMACTORS,100).
-include_lib("eunit/include/eunit.hrl").
-include("test_util.erl").
numactors() ->
	?NUMACTORS.
-define(ND1,[{name,node1},{rpcport,50001}]).
-define(ND2,[{name,node2},{rpcport,50002}]).
-define(ND3,[{name,node3},{rpcport,50003}]).
-define(ND4,[{name,node4},{rpcport,50004}]).
-define(ND5,[{name,node5},{rpcport,50005}]).
% -define(ONEGRP(XX),[[{name,"grp1"},{nodes,[butil:ds_val(name,Nd) || Nd <- XX]}]]).
% -define(TWOGRPS(X,Y),[[{name,"grp1"},{nodes,[butil:ds_val(name,Nd) || Nd <- X]}],
% 					  [{name,"grp2"},{nodes,[butil:ds_val(name,Nd) || Nd <- Y]}]]).

%{erlcmd,"../otp/bin/cerl -valgrind"},{erlenv,[{"VALGRIND_MISC_FLAGS","-v --leak-check=full --tool=memcheck --track-origins=no  "++
%                                       "--suppressions=../otp/erts/emulator/valgrind/suppress.standard --show-possibly-lost=no"}]}
cfg(Args) ->
	case Args of
		[TT|_] when TT == "single"; TT == "addsecond"; TT == "endless1"; TT == "addclusters"; TT == "mysql" ->
			Nodes = [?ND1];
			% Groups = ?ONEGRP(Nodes);
		["multicluster"|_] ->
			Nodes = [?ND1,?ND2,?ND3,?ND4];
			% Groups = ?TWOGRPS([?ND1,?ND2],[?ND3,?ND4]);
		[TT|_] when TT == "addthentake"; TT == "addcluster"; TT == "endless2" ->
			Nodes = [?ND1,?ND2];
			% Groups = ?ONEGRP(Nodes);
		{Nodes,_Groups} ->
			ok;
		[] = Nodes ->
			io:format("ERROR:~n"),
			io:format("No test type provided. Available tests: "++
			"single, cluster, multicluster, mysql, addsecond, missingnode, addthentake, addcluster, failednodes,"++
			"endless1, endless2, addclusters~n~n"),
			throw(noparam);
		_ ->
			Nodes = [?ND1,?ND2,?ND3]
			% Groups = ?ONEGRP(Nodes)
	end,
	[
		% these dtl files get nodes value as a parameter and whatever you add here.
		{global_cfg,[]},
		% Config files per node. For every node, its property list is added when rendering.
		% if name contains app.config or vm.args it gets automatically added to run node command
		% do not set cookie or name of node in vm.args this is set by detest
		{per_node_cfg,["test/etc/app.config"]},
		% cmd is appended to erl execute command, it should execute your app.
		% It can be set for every node individually. Add it to that list if you need it, it will override this value.
		{cmd,"-s actordb_core +S 2 +A 2"},

		% optional command to start erlang with
		% {erlcmd,"../otp/bin/cerl -valgrind"},

		% optional environment variables for erlang
		%{erlenv,[{"VALGRIND_MISC_FLAGS","-v --leak-check=full --tool=memcheck --track-origins=no  "++
		%                               "--suppressions=../otp/erts/emulator/valgrind/suppress.standard --show-possibly-lost=no"}]},

		% in ms, how long to wait to connect to node. If running with valgrind it takes a while.
		{connect_timeout,10000},

		% in ms, how long to wait for application start once node is started
		{app_wait_timeout,10000},

		% which app to wait for to consider node started
		{wait_for_app,actordb_core},
		% What RPC to execute for stopping nodes (optional, def. is {init,stop,[]})
		{stop,{actordb_core,stop_complete,[]}},
		{nodes,Nodes}
	].

% Before starting nodes
setup(Param) ->
	filelib:ensure_dir([butil:ds_val(path,Param),"/log"]).

% Nodes have been closed
cleanup(_Param) ->
	ok.

run(Param) ->
	[TestType|_] = butil:ds_val(args,Param),
	run(Param,TestType),
	ok.

run(Param,TType) when TType == "single"; TType == "cluster"; TType == "multicluster" ->
	Nd1 = butil:ds_val(node1,Param),
	Nd2 = butil:ds_val(node2,Param),
	Nd3 = butil:ds_val(node3,Param),
	Nd4 = butil:ds_val(node4,Param),
	Ndl = [N || N <- [Nd1,Nd2,Nd3,Nd4], N /= undefined],
	% rpc:call(Nd1,actordb_cmd,cmd,[init,commit,butil:ds_val(path,Param)++"/node1/etc"],3000),
	{ok,_} = rpc:call(Nd1,actordb_config,exec,[init(Ndl,TType)],3000),
	timer:sleep(100),
	{ok,_} = rpc:call(Nd1,actordb_config,exec_schema,[schema1()],3000),
	ok = wait_tree(Nd1,10000),
	basic_write(Ndl),
	basic_read(Ndl),
	basic_write(Ndl),
	basic_read(Ndl),
	multiupdate_write(Ndl),
	multiupdate_read(Ndl),
	kv_readwrite(Ndl),
	basic_write(Ndl),
	basic_read(Ndl),
	copyactor(Ndl),
	[detest:stop_node(Nd) || Nd <- [Nd1,Nd2,Nd3,Nd4], Nd /= undefined],
	detest:add_node(?ND1),
	case TType of
		"cluster" ->
			detest:add_node(?ND2),
			detest:add_node(?ND3);
		"multicluster" ->
			detest:add_node(?ND2),
			detest:add_node(?ND3),
			detest:add_node(?ND4);
		_ ->
			ok
	end,
	basic_write(Ndl);
run(Param,"remnode" = TType) ->
	Nd1 = butil:ds_val(node1,Param),
	Nd2 = butil:ds_val(node2,Param),
	Nd3 = butil:ds_val(node3,Param),
	Ndl = [Nd1,Nd2,Nd3],
	{ok,_} = rpc:call(Nd1,actordb_config,exec,[init(Ndl,TType)],3000),
	timer:sleep(100),
	{ok,_} = rpc:call(Nd1,actordb_config,exec_schema,[schema1()],3000),
	ok = wait_tree(Nd1,10000),
	basic_write(Ndl),
	detest:stop_node(Nd3),
	{ok,_} = rpc:call(Nd1,actordb_config,exec,["delete from nodes where name like 'node3%'"],3000),
	timer:sleep(300),
	lager:info("Nodelist now: ~p",[rpc:call(Nd1,bkdcore,nodelist,[])]),
	lager:info("Nodelist now: ~p",[rpc:call(Nd1,ets,tab2list,[globalets])]),
	ok = wait_tree(Nd1,10000),
	basic_write(Ndl),
	ok;
run(Param,"mysql" = TType) ->
	true = code:add_path("test/mysql.ez"),
	Nd1 = butil:ds_val(node1,Param),
	Ndl = [Nd1],
	% rpc:call(Nd1,actordb_cmd,cmd,[init,commit,butil:ds_val(path,Param)++"/node1/etc"],3000),
	{ok,_} = rpc:call(Nd1,actordb_config,exec,[init(Ndl,TType)],3000),
	timer:sleep(100),
	{ok,_} = rpc:call(Nd1,actordb_config,exec_schema,[schema2()],3000),
	{ok,_} = rpc:call(Nd1,actordb_config,exec,["CREATE USER 'myuser' IDENTIFIED BY 'mypass';GRANT read,write ON * to 'myuser';"],3000),

	ok = wait_tree(Nd1,10000),

	[_,Host] = string:tokens(butil:tolist(Nd1),"@"),
	MyOpt = [{host,Host},{port,butil:ds_val(rpcport,?ND1)-10000},{user,"myuser"},{password,"mypass"},{database,"actordb"}],
	{ok,Pid} = mysql:start_link(MyOpt),

	FirstInsert = [111,<<"aaaa">>,1.2],
	SecondInsert = [1,<<"insert with prepared statement!">>,3.0],
	
	ok = mysql:query(Pid, <<"actor type1(ac1) create;INSERT INTO tab VALUES (111,'aaaa',1.2);">>),
	{ok,_Cols,[FirstInsert] = _Rows} = mysql:query(Pid, <<"actor type1(ac1); select * from tab;">>),
	lager:info("Cols=~p, rows=~p", [_Cols, _Rows]),

	{ok,Id} = mysql:prepare(Pid, <<"actor type1(ac1);INSERT INTO tab VALUES ($1,$2,$3);">>),
	ok = mysql:execute(Pid,Id,SecondInsert),

	{ok,_Cols,[SecondInsert,FirstInsert] = _Rows1} = mysql:query(Pid, <<"actor type1(ac1); select * from tab;">>),
	lager:info("Cols=~p, rows=~p", [_Cols, _Rows1]),

	{ok,Id1} = mysql:prepare(Pid, <<"actor type1(ac1);select * from tab where id=$1;">>),
	{ok,_Cols,[SecondInsert] = _Rows2} = mysql:execute(Pid, Id1, [1]),
	lager:info("Using select with prepared statement: Cols=~p, rows=~p", [_Cols, _Rows2]),

	% ok = mysql:query(Pid, <<"PREPARE stmt1 () FOR type1 AS select * from tab;">>),
	% {ok,_Cols,_Rows} = PrepRes = mysql:query(Pid,<<"actor type1(ac1);EXECUTE stmt1 ();">>),
	% io:format("PrepRes ~p~n",[PrepRes]),
	ok;
run(Param,"addsecond" = TType) ->
	[Nd1,Path] = butil:ds_vals([node1,path],Param),
	Ndl = [Nd1],
	% rpc:call(Nd1,actordb_cmd,cmd,[init,commit,Path++"/node1/etc"],3000),
	{ok,_} = rpc:call(Nd1,actordb_config,exec,[init(Ndl,TType)],3000),
	timer:sleep(100),
	{ok,_} = rpc:call(Nd1,actordb_config,exec_schema,[schema1()],3000),

	ok = wait_tree(Nd1,10000),
	basic_write(Ndl),
	basic_read(Ndl),
	%test_add_second(Ndl),
	Nd2 = detest:add_node(?ND2),
	% rpc:call(Nd1,actordb_cmd,cmd,[updatenodes,commit,Path++"/node1/etc"],3000),
	{ok,_} = rpc:call(Nd1,actordb_config,exec,[nds([Nd2],1)],3000),

	ok = wait_modified_tree(Nd2,[Nd1,Nd2],30000),
	basic_write(Ndl),
	kv_readwrite(Ndl),
	multiupdate_write(Ndl),
	multiupdate_read(Ndl),
	basic_write(Ndl),
	basic_read(Ndl);
run(Param,"missingnode" = TType) ->
	Nd1 = butil:ds_val(node1,Param),
	Nd2 = butil:ds_val(node2,Param),
	Nd3 = butil:ds_val(node3,Param),
	Ndl = [Nd1,Nd2,Nd3],
	% rpc:call(Nd1,actordb_cmd,cmd,[init,commit,butil:ds_val(path,Param)++"/node1/etc"],3000),
	{ok,_} = rpc:call(Nd1,actordb_config,exec,[init(Ndl,TType)],3000),
	timer:sleep(100),
	{ok,_} = rpc:call(Nd1,actordb_config,exec_schema,[schema1()],3000),

	ok = wait_tree(Nd1,10000),
	basic_write(Ndl),
	basic_read(Ndl),
	basic_write(Ndl),
	basic_read(Ndl),
	kv_readwrite(Ndl),
	multiupdate_write(Ndl),
	multiupdate_read(Ndl),
	copyactor(Ndl),
	detest:stop_node(Nd3),
	basic_write(Ndl),
	basic_write(Ndl);
run(Param,"addthentake" = TType) ->
	Path = butil:ds_val(path,Param),
	Nd1 = butil:ds_val(node1,Param),
	Nd2 = butil:ds_val(node2,Param),
	Ndl = [Nd1,Nd2],
	% rpc:call(Nd1,actordb_cmd,cmd,[init,commit,butil:ds_val(path,Param)++"/node1/etc"],3000),
	{ok,_} = rpc:call(Nd1,actordb_config,exec,[init(Ndl,TType)],3000),
	timer:sleep(100),
	{ok,_} = rpc:call(Nd1,actordb_config,exec_schema,[schema1()],3000),

	ok = wait_tree(Nd1,10000),
	basic_write(Ndl),
	basic_read(Ndl),
	Nd3 = detest:add_node(?ND3),
	% rpc:call(Nd1,actordb_cmd,cmd,[updatenodes,commit,Path++"/node1/etc"],3000),
	{ok,_} = rpc:call(Nd1,actordb_config,exec,[nds([Nd3],1)],3000),
	ok = wait_modified_tree(Nd3,[Nd1,Nd2,Nd3],30000),
	basic_read(Ndl),
	basic_write(Ndl),
	kv_readwrite(Ndl),
	multiupdate_write(Ndl),
	multiupdate_read(Ndl),
	detest:stop_node(Nd2),
	basic_write(Ndl),
	basic_read(Ndl),
	copyactor(Ndl);
% run(Param,"addcluster") ->
% 	Nd1 = butil:ds_val(node1,Param),
% 	Nd2 = butil:ds_val(node2,Param),
% 	Ndl = [Nd1,Nd2],
% 	rpc:call(Nd1,actordb_cmd,cmd,[init,commit,butil:ds_val(path,Param)++"/node1/etc"],3000),
% 	ok = wait_tree(Nd1,10000),
% 	basic_write(Ndl),
% 	basic_read(Ndl),
% 	kv_readwrite(Ndl),
% 	Nd3 = detest:add_node(?ND3,[{global_cfg,[{"test/nodes.yaml",[{groups,?TWOGRPS([?ND1,?ND2],[?ND3,?ND4])}]},"test/schema.yaml"]}]),
% 	Nd4 = detest:add_node(?ND4,[{global_cfg,[{"test/nodes.yaml",[{groups,?TWOGRPS([?ND1,?ND2],[?ND3,?ND4])}]},"test/schema.yaml"]}]),
% 	rpc:call(Nd1,actordb_cmd,cmd,[updatenodes,commit,butil:ds_val(path,Param)++"/node1/etc"],3000),
% 	ok = wait_modified_tree(Nd3,[Nd1,Nd2,Nd3],60000),
% 	ok = wait_modified_tree(Nd4,[Nd1,Nd2,Nd3,Nd4],60000),
% 	basic_write(Ndl),
% 	basic_read(Ndl),
% 	multiupdate_write(Ndl),
% 	multiupdate_read(Ndl);
run(Param,"failednodes" = TType) ->
	Nd1 = butil:ds_val(node1,Param),
	Nd2 = butil:ds_val(node2,Param),
	Nd3 = butil:ds_val(node3,Param),
	Ndl = [Nd1],
	{ok,_} = rpc:call(Nd1,actordb_config,exec,[init(Ndl,TType)],3000),
	timer:sleep(100),
	{ok,_} = rpc:call(Nd1,actordb_config,exec_schema,[schema1()],3000),

	ok = wait_tree(Nd1,10000),
	basic_write(Ndl),
	basic_write(Ndl),
	basic_read(Ndl),
	kv_readwrite(Ndl),
	multiupdate_write(Ndl),
	multiupdate_read(Ndl),
	detest:stop_node(Nd2),
	basic_write(Ndl),
	detest:add_node(?ND2),
	basic_write(Ndl),
	detest:stop_node(Nd2),
	detest:stop_node(Nd3),
	detest:add_node(?ND2),
	detest:add_node(?ND3),
	basic_write(Ndl);
run(Param,"endless"++Num  = TType) ->
	Nd1 = butil:ds_val(node1,Param),
	NWriters = 5000,
	WriterMaxSleep = 10,
	case butil:toint(Num) of
		1 ->
			Ndl = [Nd1];
		2 ->
			Nd2 = butil:ds_val(node2,Param),
			Ndl = [Nd1,Nd2]
	end,
	{ok,_} = rpc:call(Nd1,actordb_config,exec,[init(Ndl,TType)],3000),
	timer:sleep(100),
	{ok,_} = rpc:call(Nd1,actordb_config,exec_schema,[schema1()],3000),

	ok = wait_tree(Nd1,600000),
	Home = self(),
	ets:new(writecounter, [named_table,public,set,{write_concurrency,true}]),
	butil:ds_add(wnum,0,writecounter),
	butil:ds_add(wnum_sec,0,writecounter),
	Pids = [spawn_monitor(fun() -> rseed(N),writer(Home,Nd1,N,WriterMaxSleep,0) end) || N <- lists:seq(1,NWriters)],
	lager:info("Test will run until you stop it or something crashes."),
	wait_crash(Ndl);
run(Param,"addclusters" = TType) ->
	Nd1 = butil:ds_val(node1,Param),
	Ndl = [Nd1],
	{ok,_} = rpc:call(Nd1,actordb_config,exec,[init(Ndl,TType)],3000),
	timer:sleep(100),
	{ok,_} = rpc:call(Nd1,actordb_config,exec_schema,[schema1()],3000),

	ok = wait_tree(Nd1,60000),
	AdNodesProc = spawn_link(fun() -> addclusters(butil:ds_val(path,Param),Nd1,[?ND1]) end),
	make_actors(0),
	AdNodesProc ! done;
run(Param,Nm) ->
	lager:info("Unknown test type ~p",[Nm]).

port(Nd) ->
	["node"++Num,_] = string:tokens(butil:tolist(Nd),"@"),
	50000+butil:toint(Num).

grp(N) ->
	"insert into groups values ('grp"++butil:tolist(N)++"','cluster');".
nds(Ndl,Grp) ->
	[["insert into nodes values ('",butil:tolist(Nd),":",butil:tolist(port(Nd)),"','grp",butil:tolist(Grp),"');"] || Nd <- Ndl].
usr() ->
	"CREATE USER 'root' IDENTIFIED BY 'rootpass'".

init(Ndl,TT) when TT == "single"; TT == "cluster"; TT == "addthentake"; TT == "addcluster"; TT == "endless2";
		TT == "addsecond"; TT == "endless1"; TT == "addclusters"; TT == "mysql"; TT == "remnode" ->
	[grp(1),nds(Ndl,1),usr()];
init([N1,N2,N3,N4],"multicluster") ->
	[grp(1),grp(2),nds([N1,N2],1),nds([N3,N4],2),usr()].

schema1() ->
	["actor type1;",
	"CREATE TABLE tab (id INTEGER PRIMARY KEY, txt TEXT, i INTEGER);",
	"CREATE TABLE tab1 (id INTEGER PRIMARY KEY, txt TEXT);",
	"CREATE TABLE tab2 (id INTEGER PRIMARY KEY, txt TEXT);",
	"actor thread;",
	"CREATE TABLE thread (id INTEGER PRIMARY KEY, msg TEXT, user INTEGER);",
	"actor user;",
	"CREATE TABLE userinfo (id INTEGER PRIMARY KEY, name TEXT);",
	"actor counters kv;",
	"CREATE TABLE actors (id TEXT UNIQUE, hash INTEGER, val INTEGER);",
	"actor filesystem kv;",
	"CREATE TABLE actors (id TEXT UNIQUE, hash INTEGER, size INTEGER);",
	"CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, fileid TEXT, uid INTEGER, FOREIGN KEY (fileid) REFERENCES actors(id) ON DELETE CASCADE);"].

schema2() ->
	["actor type1;",
	"CREATE TABLE tab (id INTEGER PRIMARY KEY, txt TEXT, i FLOAT);"].
