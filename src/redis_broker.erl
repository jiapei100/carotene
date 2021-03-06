-module(redis_broker).

-behaviour(gen_server).
-export([start_link/1, start/1, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, terminate/2, handle_info/2, code_change/3]).

-record(state, {client, subclient, supervisor, redis_subscriber_supervisor, smart_sub}).

start_link(Sup) ->
    Opts = [],
    gen_server:start_link(?MODULE, [Sup], Opts).

start(Sup) ->
    Opts = [],
    gen_server:start(?MODULE, [Sup], Opts).

stop(Pid) ->
    gen_server:call(Pid, stop, infinity).

init([Sup]) ->
    {ok, Client} = eredis:start_link(),
    {ok, SubClient} = eredis_sub:start_link(),
    {ok, SmartSubClient} = eredis_smart_sub:start_link(SubClient),
    self() ! {start_redis_subscriber_sup, SmartSubClient},
    {ok, #state{client = Client, supervisor = Sup}}.

handle_info({start_redis_subscriber_sup, SmartSubClient}, State = #state{supervisor = Sup}) ->
    {ok, SubscriberSup} = supervisor:start_child(Sup, {redis_subscriber_sup,
          {redis_subscriber_sup, start_link, [SmartSubClient]},
          permanent,
          infinity,
          supervisor,
          [redis_subscriber_sup]}),
    {noreply, State#state{redis_subscriber_supervisor = SubscriberSup}};

handle_info(shutdown, State) ->
    {stop, normal, State}.

handle_call(start_subscriber, _From, State = #state{redis_subscriber_supervisor = SubscriberSup}) ->
    {ok, Subscriber} = supervisor:start_child(SubscriberSup, []),

    {reply, {ok, Subscriber}, State};

handle_call(stop, _From, State) ->
    {stop, normal, ok, State}.

handle_cast({publish, Message, channel, Channel}, State = #state{client = Client}) ->
    eredis:q(Client, ["PUBLISH", Channel, Message]),
    {noreply, State};

handle_cast(_Message, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    State.
