%%%----------------------------------------------------------------------
%%% Purpose : Implements hashing functionality for fragmented tables
%%%----------------------------------------------------------------------
%%%
%%% This module is mainly copied from the default module mnesia_frag_hash,
%%% except using partial key for hash, to be exact, the first X (default two)
%%% elements of the key tuple, to make data with same prefix get together.
%%%
%%%----------------------------------------------------------------------

-module(mnesia_frag_hash_partial).
-author('eric@easemob.com').

%% Fragmented Table Hashing callback functions
-export([init_state/2,
		 add_frag/1,
		 del_frag/1,
		 key_to_frag_number/2,
		 match_spec_to_frag_numbers/2]).

-export([extract_partial_key/1]).

-record(hash_state,
		{n_fragments,
		 next_n_to_split,
		 n_doubles,
		 n_parts_of_key,
		 function}).

-define(N_PARTS_OF_KEY, 2).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

init_state(_Tab, State) when State == undefined ->
    #hash_state{n_fragments     = 1,
				next_n_to_split = 1,
				n_doubles       = 0,
				function        = phash2}.

convert_old_state({hash_state, N, P, L}) ->
    #hash_state{n_fragments     = N,
				next_n_to_split = P,
				n_doubles       = L,
				function        = phash}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

add_frag(#hash_state{next_n_to_split = SplitN, n_doubles = L, n_fragments = N} = State) ->
    P = SplitN + 1,
    NewN = N + 1,
    State2 = case power2(L) + 1 of
				 P2 when P2 == P ->
					 State#hash_state{n_fragments      = NewN,
									  n_doubles        = L + 1,
									  next_n_to_split  = 1};
				 _ ->
					 State#hash_state{n_fragments     = NewN,
									  next_n_to_split = P}
			 end,
    {State2, [SplitN], [NewN]};
add_frag(OldState) ->
    State = convert_old_state(OldState),
    add_frag(State).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

del_frag(#hash_state{next_n_to_split = SplitN, n_doubles = L, n_fragments = N} = State) ->
    P = SplitN - 1,
    if
		P < 1 ->
			L2 = L - 1,
			MergeN = power2(L2),
			State2 = State#hash_state{n_fragments     = N - 1,
									  next_n_to_split = MergeN,
									  n_doubles       = L2},
			{State2, [N], [MergeN]};
		true ->
			MergeN = P,
			State2 = State#hash_state{n_fragments     = N - 1,
									  next_n_to_split = MergeN},
			{State2, [N], [MergeN]}
	end;
del_frag(OldState) ->
    State = convert_old_state(OldState),
    del_frag(State).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

key_to_frag_number(State, Key) when is_tuple(Key) andalso
									tuple_size(Key) > ?N_PARTS_OF_KEY ->
	key_to_frag_number(State, to_partial_key(Key));

key_to_frag_number(#hash_state{function = phash, n_fragments = N, n_doubles = L}, Key) ->
    A = erlang:phash(Key, power2(L + 1)),
    if A > N ->
			A - power2(L);
	   true ->
			A
    end;
key_to_frag_number(#hash_state{function = phash2, n_fragments = N, n_doubles = L}, Key) ->
    A = erlang:phash2(Key, power2(L + 1)) + 1,
    if A > N ->
			A - power2(L);
	   true ->
			A
    end;
key_to_frag_number(OldState, Key) ->
    State = convert_old_state(OldState),
    key_to_frag_number(State, Key).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

match_spec_to_frag_numbers(#hash_state{n_fragments = N} = State, MatchSpec) ->
    case MatchSpec of
		[{HeadPat, MatchCond, _}] when is_tuple(HeadPat), tuple_size(HeadPat) > 2 ->
			KeyPat = element(2, HeadPat),
			case has_var(KeyPat) of
				false ->
					[key_to_frag_number(State, KeyPat)];
				true ->
					case extract_partial_key(MatchCond) of
						undefined ->
							lists:seq(1, N);
						PartialKey ->
							[key_to_frag_number(State, PartialKey)]
					end
			end;
		_ ->
			lists:seq(1, N)
    end;
match_spec_to_frag_numbers(OldState, MatchSpec) ->
    State = convert_old_state(OldState),
    match_spec_to_frag_numbers(State, MatchSpec).

power2(Y) ->
    1 bsl Y. % trunc(math:pow(2, Y)).

has_var(Pat) ->
    mnesia:has_var(Pat).

to_partial_key(Key) when is_tuple(Key) andalso
						 tuple_size(Key) >= ?N_PARTS_OF_KEY->
	list_to_tuple(lists:sublist(tuple_to_list(Key), ?N_PARTS_OF_KEY));
to_partial_key(Key) ->
	Key.

extract_partial_key([]) ->
	undefined;
extract_partial_key([{'/=', as_partial_key, {Key}}|_]) ->
	to_partial_key(Key);
extract_partial_key([_G|MatchCond]) ->
	extract_partial_key(MatchCond).
