 %%%-------------------------------------------------------------------
%%% @author Heinz Nikolaus Gies <heinz@licenser.net>
%%% @copyright (C) 2013, Heinz Nikolaus Gies
%%% @doc
%%%
%%% @end
%%% Created :  9 Jun 2013 by Heinz Nikolaus Gies <heinz@licenser.net>
%%%-------------------------------------------------------------------
-module(rot).

-ifdef(TEST).
-include_lib("proper/include/proper.hrl").
-include_lib("eunit/include/eunit.hrl").
-endif.
-define(DEFAULT_SIZE, 100).

-record(rot, {newest = 0 :: term(),
              count = 0 :: pos_integer(),
              leave = true :: boolean(),
              size = ?DEFAULT_SIZE,
              hash = undefined :: undefined | binary(),
              elements = [] :: []}).

-export([new/1, new/2, add/2, value/1, full/1]).

new(ID) ->
    #rot{newest = ID}.

new(ID, Size) ->
    #rot{newest = ID,
         size = Size}.


add(E, ROT) ->
    case radd(E, ROT) of
        {ok, Res} ->
            Res;
        {branch, ROT1, E1} ->
            branch(E1, ROT1)
    end.

value(#rot{leave = true,
           elements = Es}) ->
    Es;

value(#rot{elements = [E]}) ->
    ordsets:from_list(value(E));
value(#rot{elements = [E0 | Es]}) ->
    ordsets:from_list(value(Es, value(E0))).

full(#rot{leave = true,
          newest = N,
          hash = H}) ->
    full([{N, H}], []);
full(#rot{elements = Es}) ->
    full(Es, []).



%%%===================================================================
%%% Internal functions
%%%===================================================================
full([], Acc) ->
    Acc;
full([#rot{leave = true,
           newest = N,
           hash = H,
           count = _S,
           size = _S} | Rs], Acc) ->
    full(Rs, ae({N, H}, Acc));
full([#rot{leave = true} | Rs], Acc) ->
    full(Rs, Acc);
full([#rot{hash = undefined, elements = Es} | Rs], Acc) ->
    Acc1 = full(Es, Acc),
    full(Rs, Acc1);
full([#rot{newest = N,
           hash = H,
           elements = Es} | Rs], Acc) ->
    Acc1 = full(Es, ae({N, H}, Acc)),
    full(Rs, Acc1).

value([], Acc) ->
    lists:reverse(Acc);
value([E0 | R], Acc) ->
    value(R, ordsets:union(value(E0), Acc)).

hash(#rot{hash = Hash}) when is_binary(Hash) ->
    Hash;

hash(#rot{leave = true,
          count = _S,
          size = _S,
          elements = Es}) ->
    crypto:sha(term_to_binary(Es));

hash(#rot{leave = true}) ->
    undefined;

hash(#rot{leave = false,
          elements = Es}) ->
    H = lists:foldl(fun(_, undefined) ->
                            undefined;
                       (ROT, Hash) ->
                            case hash(ROT) of
                                undefined ->
                                    undefined;
                                H0 ->
                                    crypto:sha_update(Hash, H0)
                            end
                    end, crypto:sha_init(), Es),
    case H of
        undefined ->
            undefined;
        _ ->
            crypto:sha_final(H)
    end.

clone(ROT) ->
    ROT#rot{
      newest = undefined,
      hash = undefined,
      elements = [],
      count = 0}.

branch(E, ROT) ->
    ROT1 = add(E, clone(ROT)),
    [#rot{newest = N} |_] = Es = ordsets:from_list([ROT, ROT1]),
    Res = clone(ROT),
    Res#rot{leave = false,
            count = 2,
            newest = N,
            elements = Es}.

radd(E,
     #rot{count = Cnt,
          size = Size,
          leave = true,
          elements = Es} = ROT) when Cnt < Size ->
    [{Newest, _} | _] = Es1 = ordsets:add_element(E, Es),
    Cnt1 = Cnt + 1,
    ROT1 = ROT#rot{newest = Newest,
                   count = Cnt + 1,
                   elements = Es1},
    Hash = case Cnt1 of
               S when S =:= Size ->
                   hash(ROT1);
               _ ->
                   undefined
           end,
    {ok, ROT1#rot{hash = Hash}};

radd(E, #rot{newest = _Newest,
             leave = true,
             elements = Es} = ROT) ->
    [F | Es1] = ordsets:add_element(E, Es),
    [{Newest, _} | _ ] = Es1,
    ROT1 = ROT#rot{newest = Newest,
                   elements = Es1},
    Hash = hash(ROT1),
    {branch, ROT1#rot{hash = Hash}, F};

radd(E, ROT = #rot{elements = Es,
                   leave = false}) ->
    case add_to_elements(E, Es, []) of
        {ok, Es1, []} ->
            case length(Es1) of
                Cnt when Cnt =:= ROT#rot.size ->
                    [#rot{newest = Newest} | _] = Es1,
                    ROT1 = ROT#rot{elements = Es1,
                                   count = Cnt,
                                   newest = Newest},
                    Hash = hash(ROT1),
                    {ok, ROT1#rot{hash = Hash}};
                Cnt when Cnt > ROT#rot.size ->
                    [Eup | [#rot{newest = Newest} | _] = Es2] = Es1,
                    ROT1 = ROT#rot{elements = Es2,
                                   newest = Newest,
                                   count = Cnt - 1},
                    Hash = hash(ROT1),
                    {branch, ROT1#rot{hash = Hash}, Eup};
                Cnt ->
                    [#rot{newest = Newest} | _] = Es1,
                    {ok, ROT#rot{hash = undefined,
                                 newest = Newest,
                                 elements = Es1,
                                 count = Cnt}}
            end;
        {branch, Es1, E1, []} ->
            ROT1 = ROT#rot{elements = Es1},
            Hash = hash(ROT1),
            {branch, ROT1#rot{hash = Hash}, E1}
    end.

add_to_elements(E, [], []) ->
    {ok, [E], []};

add_to_elements({ID, _E} = E0,
                [#rot{newest = _N1} = ROT1,
                 #rot{newest = _N2} = ROT2
                 | R],
                Acc) when ID =< _N1,
                          ID > _N2 ->
    do_add(E0, ROT1, ae(ROT2,  R), Acc);

add_to_elements(E0,
                [ROT1],
                Acc)  ->
    do_add(E0, ROT1, [], Acc);

add_to_elements(E0,
                [ROT1 | R],
                Acc)  ->
    case add_to_elements(E0, R, [ROT1 | Acc]) of
        {ok, Rest, [A0 | Acc1]} ->
            {ok, [A0 |Rest],  Acc1};
        {ok, Rest, []} ->
            {ok, Rest,  []};
        {branch, Rest, E, [A0 | Acc]} ->
            case radd(E, A0) of
                {ok, A1} ->
                    {ok, ae(A1, Rest), Acc};
                {branch, A1, E1} ->
                    {branch, ae(A1, Rest), E1, Acc}
            end;
        {branch, Rest, E, []} ->
            case radd(E, clone(ROT1)) of
                {ok, A1} ->
                    {ok, ae(A1, Rest), Acc};
                {branch, A1, E1} ->
                    {branch, ae(A1, Rest), E1, Acc}
            end

    end.

do_add(E, ROT1, Rest, [ROT2 | Acc]) ->
    case radd(E, ROT1) of
        {ok, ROTR} ->
            {ok, ae(ROT2, ae(ROTR, Rest)), Acc};
        {branch, ROTR, E1} ->
            case radd(E1, ROT2) of
                {ok, ROTR1} ->
                    {ok, ae(ROTR1, ae(ROTR,  Rest)), Acc};
                {branch, ROTR1, E2} ->
                    {branch, ae(ROTR1, ae(ROTR, Rest)), E2, Acc}
            end
    end;

do_add(E, ROT1, Rest, []) ->
    case radd(E, ROT1) of
        {ok, ROTR} ->
            {ok, ae(ROTR,  Rest), []};
        {branch, ROTR, E1} ->
            {branch, [ROTR], E1, []}
    end.

ae(E, S) ->
    ordsets:add_element(E, S).

-ifdef(TEST).

%% Applies the list of opperaitons to three empty sets.
apply_ops(Values) ->
    lists:foldl(fun(E, {ROT, Ordset}) ->
                        Element = {now(), E},
                        {add(Element, ROT), ordsets:add_element(Element, Ordset)}
                end, {new(now(), 3), ordsets:new()}, Values).

prop_tor() ->
    ?FORALL(Ts,  [pos_integer()],
            begin
                {ROT, Orset} = apply_ops(Ts),
                value(ROT) =:= Orset
            end).

propper_test() ->
    ?assertEqual([], proper:module(?MODULE, [{to_file, user}, long_result])).


-endif.

-ifdef(BLA).
test() ->
    rot:add({now(), 4}, rot:add({now(), 3}, rot:add({now(), 2}, rot:add({now(), 1}, rot:new(now(), 2))))).

-endif.