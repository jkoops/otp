%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 1996-2010. All Rights Reserved.
%%
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%%
%% %CopyrightEnd%
%%

%%
-module(mnesia_install_test).
-author('hakan@erix.ericsson.se').

-compile([export_all]).
-include("mnesia_test_lib.hrl").

init_per_testcase(Func, Conf) ->
    mnesia_test_lib:init_per_testcase(Func, Conf).

fin_per_testcase(Func, Conf) ->
    mnesia_test_lib:fin_per_testcase(Func, Conf).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
all(doc) ->
    ["Run some small but demanding test cases in order to verify",
     "that the basic functionality in Mnesia still works.",
     "",
     "Try some very simple things to begin with and increase the",
     "difficulty stepwise. This test suite should be run before",
     "all the others if you expect to find bugs.",
     "",
     "The function mnesia_install_test:silly() does not use the whole",
     "infra structure of the test suite. Invoke it on a single node to",
     "begin with. If that works, proceed with pong = net_adm:ping(SomeOtherNode)",
     "and rerun silly() in order to perform some distributed tests."];
all(suite) ->
    [
     silly_durability,
     silly_move,
     silly_upgrade
     %,stress
    ].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Stepwise of more and more advanced features
silly() ->
    Nodes = [node()] ++ nodes(),
    mnesia_test_lib:kill_mnesia(Nodes),
    Config = [{nodes, Nodes}],
    mnesia_test_lib:eval_test_case(?MODULE, silly2, Config).

silly2(Config) when is_list(Config) ->
    [Node1 | _] = Nodes = ?acquire_nodes(3, Config),
    mnesia_test_lib:kill_mnesia(Nodes),
    ?ignore([mnesia:delete_schema([N]) || N <- Nodes]),
    ?match(ok, mnesia:create_schema([Node1])),
    ?match(ok, rpc:call(Node1, mnesia, start, [])),
    ?match(ok, rpc:call(Node1, mnesia, wait_for_tables,
			[[schema], infinity])),
    Res = silly_durability(Config),
    StressFun = fun(F) -> apply(?MODULE, F, [Config]) end,
    R =
	case length(Nodes) of
	    L when L > 1 ->
		Node2 = lists:nth(2, Nodes),
		AddDb = [schema, Node2, ram_copies],
		?match({atomic, ok},
		       rpc:call(Node1, mnesia, add_table_copy, AddDb)),
		Args = [[{extra_db_nodes, [Node1]}]],
		?match(ok, rpc:call(Node2, mnesia, start, Args)),
		ChangeDb = [schema, Node2, disc_copies],
		?match({atomic, ok},
		       rpc:call(Node1, mnesia, change_table_copy_type,
				ChangeDb)),
		?match([], mnesia_test_lib:sync_tables([Node1, Node2],
						       [schema])),
		MoveRes = silly_move(Config),
		UpgradeRes = silly_upgrade(Config),
		StressRes = [StressFun(F) || F <- stress(suite)],
		?verify_mnesia([Node2], []),
		[Res, MoveRes, UpgradeRes] ++ StressRes;
	    _ ->
		StressRes = [StressFun(F) || F <- stress(suite)],
		?warning("Too few nodes. Perform net_adm:ping(OtherNode) "
			 "and rerun!!!~n", []),
		[Res | StressRes]
	end,
    ?verify_mnesia([Node1], []),
    R.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
silly_durability(doc) ->
    ["Simple test of durability"];
silly_durability(suite) -> [];
silly_durability(Config) when is_list(Config) ->
    [Node1] = ?acquire_nodes(1, Config),
    Tab = silly,
    Storage = mnesia_test_lib:storage_type(disc_copies, Config),   
    
    ?match({atomic, ok}, rpc:call(Node1, mnesia, 
				  create_table, [Tab, [{Storage, [Node1]}]])),

    Read = fun() -> mnesia:read({Tab, a}) end,
    Write = fun() -> mnesia:write({Tab, a, b}) end,

    ?match({atomic, []},
	   rpc:call(Node1, mnesia, transaction, [Read])),
    ?match({atomic, ok},
	   rpc:call(Node1, mnesia, transaction, [Write])),
    ?match({atomic, [{Tab, a, b}]}, 
	   rpc:call(Node1, mnesia, transaction, [Read])),
    
    ?match(stopped, rpc:call(Node1, mnesia, stop, [])),
    ?match(ok, rpc:call(Node1, mnesia, start, [])),
    case mnesia_test_lib:diskless(Config) of
	true -> 
	    skip;
	false ->
	    ?match(ok, rpc:call(Node1, mnesia, wait_for_tables, [[Tab], infinity])),	    
	    ?match({atomic, [{Tab, a, b}]},
		   rpc:call(Node1, mnesia, transaction, [Read]))
    end,
    ?verify_mnesia([Node1], []).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
silly_move(doc) ->
    ["Simple test of movement of a replica from one node to another"];
silly_move(suite) -> [];
silly_move(Config) when is_list(Config) ->
    [Node1, Node2] = ?acquire_nodes(2, Config),
    Tab = silly_move,
    ?match({atomic, ok},
	   rpc:call(Node1, mnesia,
		    create_table, [Tab, [{ram_copies, [Node2]}]])),
    ?match([], mnesia_test_lib:sync_tables([Node1, Node2], [Tab])),

    Read = fun() -> mnesia:read({Tab, a}) end,
    Write = fun() -> mnesia:write({Tab, a, b}) end,

    ?match({atomic, []},
	   rpc:call(Node1, mnesia, transaction, [Read])),
    ?match({atomic, ok},
	   rpc:call(Node1, mnesia, transaction, [Write])),
    ?match({atomic, [{Tab, a, b}]}, 
	   rpc:call(Node1, mnesia, transaction, [Read])),
    
    case mnesia_test_lib:diskless(Config) of
	true -> skip;
	false -> 
	    ?match({atomic, ok}, 
		   rpc:call(Node1, mnesia,
			    change_table_copy_type, [Tab, Node2, disc_only_copies])),
	    ?match([], mnesia_test_lib:sync_tables([Node1, Node2], [Tab]))
    end,
    ?match({atomic, [{Tab, a, b}]}, rpc:call(Node1, mnesia, transaction, [Read])),

    ?match({atomic, ok},
	   rpc:call(Node1, mnesia,
		    move_table_copy, [Tab, Node2, Node1])),
    ?match([], mnesia_test_lib:sync_tables([Node1, Node2], [Tab])),
    ?match({atomic, [{Tab, a, b}]},
	   rpc:call(Node1, mnesia, transaction, [Read])),
    ?verify_mnesia([Node1], []).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
silly_upgrade(doc) ->
    ["Simple test of a schema upgrade and restore from backup"];
silly_upgrade(suite) -> [];
silly_upgrade(Config) when is_list(Config) ->
    [Node1, Node2] = Nodes = ?acquire_nodes(2, Config),
    Name = silly_upgrade,
    Tab1 = silly_upgrade1,
    Tab2 = silly_upgrade2,
    Bup = "silly_upgrade.BUP",
    Bup2 = "silly_upgrade_part.BUP",
    ?match({atomic, ok}, mnesia:create_table(Tab1, [{ram_copies, Nodes}])),
    ?match({atomic, ok}, mnesia:create_table(Tab2, [{disc_only_copies, Nodes}])),

    CpState = add_some_records(Tab1, Tab2, []),
    ?match(match, verify_state(Tab1, Tab2, CpState)),
    file:delete(Bup),
    ?match(ok, mnesia:backup(Bup)),
    Args = [{name, Name}, {ram_overrides_dump, true},
	    {min, [Tab1, schema]}, {max, [Tab2]}],
    ?match({ok, Name, _}, mnesia:activate_checkpoint(Args)),

    IgnoreState = add_more_records(Tab1, Tab2, CpState),
    ?match(match, verify_state(Tab1, Tab2, IgnoreState)),
    ?match({mismatch, _, _}, verify_state(Tab1, Tab2, CpState)),
    ?match({atomic, ok}, mnesia:del_table_copy(Tab2, Node1)),
    file:delete(Bup2),
    ?match(ok, mnesia:backup_checkpoint(Name, Bup2)),

    UpgradeState = transform_some_records(Tab1, Tab2, IgnoreState),
    ?match({mismatch, _, _}, verify_state(Tab1, Tab2, CpState)),
    ?match({mismatch, _, _}, verify_state(Tab1, Tab2, IgnoreState)),
    ?match(match, verify_state(Tab1, Tab2, UpgradeState)),

    ?match(ok, mnesia:deactivate_checkpoint(Name)),
    ?match(match, verify_state(Tab1, Tab2, UpgradeState)),

    ?match(ok, mnesia:install_fallback(Bup2)),
    file:delete(Bup2),
    %% Will generate intentional crash, fatal error
    ?match([], mnesia_test_lib:stop_mnesia([Node2])),  
    wait_till_dead([Node1, Node2]),
    ?match([], mnesia_test_lib:start_mnesia([Node1, Node2], [Tab1, Tab2])),
    ?match(match, verify_state(Tab1, Tab2, CpState)),

    ?match(ok, mnesia:install_fallback(Bup)),
    file:delete(Bup),
    %% Will generate intentional crash, fatal error
    ?match([], mnesia_test_lib:stop_mnesia([Node1, Node2])),  
    wait_till_dead([Node1, Node2]),
    ?match([], mnesia_test_lib:start_mnesia([Node1, Node2], [Tab1, Tab2])),
    CpState2 = [X || X <- CpState, element(1, X) /= Tab1],
    ?match(match, verify_state(Tab1, Tab2, CpState2)),
    ?verify_mnesia(Nodes, []).

wait_till_dead([]) -> ok;
wait_till_dead([N|Ns]) ->
    Apps = rpc:call(N, application, which_applications, []),
    case lists:keymember(mnesia, 1, Apps) of
	true -> 
	    timer:sleep(10),
	    wait_till_dead([N|Ns]);
	false -> 
	    wait_till_dead(Ns)
    end.

add_some_records(Tab1, Tab2, Old) ->
    Recs1 = [{Tab1, I, I} || I <- lists:seq(1, 30)],
    Recs2 = [{Tab2, I, I} || I <- lists:seq(20, 40)],
    lists:foreach(fun(R) -> mnesia:dirty_write(R) end, Recs1),
    Fun = fun(R) -> mnesia:write(R) end,
    Trans = fun() -> lists:foreach(Fun, Recs2) end,
    ?match({atomic, _}, mnesia:transaction(Trans)),
    lists:sort(Old ++ Recs1 ++ Recs2).

add_more_records(Tab1, Tab2, Old) ->
    Change1 = [{T, K, V+100} || {T, K, V} <- Old, K==23],
    Change2 = [{T, K, V+100} || {T, K, V} <- Old, K==24],
    Del = [{T, K} || {T, K, _V} <- Old, K>=25],
    New = [{Tab1, 50, 50}, {Tab2, 50, 50}],
    lists:foreach(fun(R) -> mnesia:dirty_write(R) end, Change1),
    lists:foreach(fun(R) -> mnesia:dirty_delete(R) end, Del),
    Fun = fun(R) -> mnesia:write(R) end,
    Trans = fun() -> lists:foreach(Fun, Change2 ++ New) end,
    ?match({atomic, ok}, mnesia:transaction(Trans)),
    Recs = [{T, K, V} || {T, K, V} <- Old, K<23] ++ Change1 ++ Change2 ++ New,
    lists:sort(Recs).


verify_state(Tab1, Tab2, Exp) ->
    Fun = fun() ->
		  Act1 = [mnesia:read({Tab1, K}) || K <- mnesia:all_keys(Tab1)],
		  Act2 = [mnesia:read({Tab2, K}) || K <- mnesia:all_keys(Tab2)],
		  Act = lists:append(Act1) ++ lists:append(Act2),
		  {ok, Act -- Exp, Exp -- Act}
	  end,
    case mnesia:transaction(Fun) of
	{atomic, {ok, [], []}} -> match;
	{atomic, {ok, More, Less}} -> {mismatch, More, Less};
	{aborted, Reason} -> {error, Reason}
    end.

transform_some_records(Tab1, _Tab2, Old) ->
     Fun = fun(Rec) ->
		   list_to_tuple(tuple_to_list(Rec) ++ [4711])
	   end,
    ?match({atomic, ok},
	   mnesia:transform_table(Tab1, Fun, [key, val, extra])),
    Filter = fun(Rec) when element(1, Rec) == Tab1 -> {true, Fun(Rec)};
		(_) -> true
	     end,
    lists:sort(lists:zf(Filter, Old)).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
stress(doc) ->
    ["Stress the system a little"];
stress(suite) ->
    [
     conflict,
     dist
    ].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
dist(doc) ->
    ["Avoid lock conflicts in order to maximize thruput",
     "Ten drivers per node, tables replicated to all nodes, lots of branches"];
dist(suite) -> [];
dist(Config) when is_list(Config) ->
    Nodes = ?acquire_nodes(3, Config ++ [{tc_timeout, 10 * 60000}]),
    Storage = mnesia_test_lib:storage_type(disc_copies, Config),
    ?match({ok, _}, mnesia_tpcb:start(dist_args(Nodes, Storage))).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
conflict(doc) ->
    ["Provoke a lot of lock conflicts.",
     "Ten drivers per node, tables replicated to all nodes, single branch"];
conflict(suite) -> [];
conflict(Config) when is_list(Config) ->
    Nodes = ?acquire_nodes(3, Config ++ [{tc_timeout, 10 * 60000}]),
    Storage = mnesia_test_lib:storage_type(disc_copies, Config),
    ?match({ok, _}, mnesia_tpcb:start(conflict_args(Nodes, Storage))).

conflict_args(Nodes, ReplicaType) ->
    [{db_nodes, Nodes},
     {driver_nodes, Nodes},
     {replica_nodes, Nodes},
     {n_drivers_per_node, 10},
     {n_branches, 1},
     {n_accounts_per_branch, 10},
     {replica_type, ReplicaType},
     {stop_after, timer:minutes(5)},
     {report_interval, timer:seconds(10)},
     {use_running_mnesia, true},
     {reuse_history_id, true}].

dist_args(Nodes, ReplicaType) ->
    [{db_nodes, Nodes},
     {driver_nodes, Nodes},
     {replica_nodes, Nodes},
     {n_drivers_per_node, 10},
     {n_branches, length(Nodes) * 100},
     {n_accounts_per_branch, 10},
     {replica_type, ReplicaType},
     {stop_after, timer:minutes(5)},
     {report_interval, timer:seconds(10)},
     {use_running_mnesia, true},
     {reuse_history_id, true}].

