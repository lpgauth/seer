-module(seer_server).

-include("seer.hrl").

-behaviour(gen_server).

-export(
    [
        init/1,
        handle_cast/2,
        handle_call/3,
        handle_info/2,
        terminate/2,
        code_change/3
    ]
).
-export([start_link/0]).

-record(
    state,
    {
        mode :: undefined | stdout,
        prefix :: undefined | binary(),
        host :: undefined | binary()
    }
).

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init(_) ->
    Mode = ?ENV(?ENV_MODE, ?DEFAULT_MODE),
    Prefix = ?ENV(?ENV_PREFIX, ?DEFAULT_PREFIX),
    Host = ?ENV(?ENV_HOST, ?DEFAULT_HOST),
    Interval = ?ENV(?ENV_INTERVAL, ?DEFAULT_INTERVAL),
    Msg =
        case Mode of
            stdout -> poll_stdout;
            carbon -> poll_carbon
        end,
    timer:send_interval(Interval, Msg),
    {ok, #state{mode = Mode, prefix = Prefix, host = Host}, 0}.

handle_call(_, _From, State) -> {reply, {error, undefined_call}, State}.

handle_cast(stop, State) -> {stop, normal, State};
handle_cast(_, State) -> {noreply, State}.

handle_info(poll_stdout, State) ->
    Metrics = seer:read_all(),
    io:format("~w~n", [Metrics]),
    {noreply, State};
handle_info(poll_carbon, #state{prefix = Prefix, host = Host} = State) ->
    Metrics = seer:read_all(),
    CarbonStrings = seer_utils:carbon_format(Prefix, Host, Metrics),
    case
    gen_tcp:connect(
        ?ENV(?ENV_CARBON_HOST, ?DEFAULT_CARBON_HOST),
        ?ENV(?ENV_CARBON_PORT, ?DEFAULT_CARBON_PORT),
        [binary]
    ) of
        {ok, Socket} ->
            [gen_tcp:send(Socket, Metric) || Metric <- CarbonStrings],
            gen_tcp:close(Socket);
        {error, Reason} ->
            % TODO: put metrics in buffer and loop for connection
            io:format("~s~n", [Reason])
    end,
    {noreply, State};
handle_info(_, State) -> {noreply, State}.

terminate(_Reason, _State) -> ok.

code_change(_OldVsn, State, _Extra) -> {ok, State}.
