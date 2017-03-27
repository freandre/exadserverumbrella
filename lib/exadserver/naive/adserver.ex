defmodule ExAdServer.Naive.AdServer do
  @compile {:parse_transform, :ms_transform}

  import ExAdServer.Utils.Storage

  alias :ets, as: ETS
  use GenServer

  ## Client API

  @doc """
  Starts the server.
  """
  def start_link do
    GenServer.start_link(__MODULE__, :ok, [])
  end

  @doc """
  Add or update an ad to the store
  """
  def loadAd(server, %{"adid" => _, "targeting" => _} = ad) do
    GenServer.call(server, {:load, ad})
  end

  @doc """
  Retrieve an ad by its id

  Returns the ad or :notfound
  """
  def getAd(server, adId) do
    GenServer.call(server, {:getAd, adId})
  end

  @doc """
  Main function for filtering ads based on received criteria

  Returns [ads] if something match or []
  In case of targeting argument not supported, :badArgument
  """
  def filterAd(server, adRequest) do
    GenServer.call(server, {:filter, adRequest})
  end

  ## Server Callbacks

  ## init callback, we initialize the main store as well as an empty index registry
  def init(:ok) do
    adsStore = ETS.new(:adsStore, [:set, :protected])
    indexes = %{}
    {:ok, [adsStore: adsStore, indexes: indexes]}
  end

  ## handle_call callback for :load action, iterate on targeting keys creating
  ## an index for each
  def handle_call({:load, ad}, _from, state) do
    ETS.insert(state[:adsStore], {ad["adid"], ad})
    state = Keyword.put(state, :indexes,
              Enum.reduce(ad["targeting"], state[:indexes], &createIndex(&1, ad["adid"], &2))
            )
    {:reply, :ok, state}
  end

  ## handle_call callback for :getAd, perform a lookup on main  ad table
  def handle_call({:getAd, adId}, _from, state) do
    case ETS.lookup(state[:adsStore], adId) do
      [] -> {:reply, :notfound, state}
      [{^adId, ad}] -> {:reply, ad, state}
    end
  end

  ## handle_call callback for :filter, performs some targeting based on a
  ## targeting request
  def handle_call({:filter, adRequest}, _from, state) do
    indexes = state[:indexes]

    case validateRequest(adRequest, indexes) do
      :ok -> {:reply, filterRequest(adRequest, indexes, state[:adsStore]), state}
      reason -> {:reply, {:badArgument, reason}, state}
    end
  end

  ## Private functions

  ## Create an index based on given index data
  defp createIndex({indexName, indexData}, adId, indexes) do
    {store, indexes} = getStore(indexName, indexes)
    Enum.each(indexData["data"], &ETS.insert(store, {{indexData["inclusive"], &1}, adId}))
    indexes
  end

  ## Validate that a filtering request provides a set of know targets
  defp validateRequest(adRequest, indexes) do
    answer = adRequest
             |> Enum.filter(fn({ixName, _}) -> !Map.has_key?(indexes, ixName) end)
             |> Enum.map(fn({ixName, _}) -> ixName end)
             |> Enum.reduce("", fn(ixName, acc) -> acc <> ixName end)

    case answer do
      "" -> :ok
      _ -> "The following target attributes are not available: " <> answer
    end
  end

  ## Main filtering function, thanks to an accumulator initalized to all ad values,
  ## we iterate on index removing datas from this accumulator
  defp filterRequest(adRequest, indexes, adsStore) do
    Enum.reduce(adRequest,
         MapSet.new(ETS.select(adsStore, ETS.fun2ms(fn({adId, _}) -> adId end))),
         fn({indexName, indexValue}, acc) ->
           case MapSet.size(acc) do
             0 -> acc
             _ -> findInIndex(indexes[indexName], indexValue)
                  |> MapSet.intersection(acc)
           end
         end)
  end

  ## Look values in an index :  we first filter all inclusive data and remove the
  ## exluding ones
  defp findInIndex(etsStore, value) do
    included = MapSet.new(ETS.select(etsStore,
                 ETS.fun2ms(fn({{inclusive, storedValue}, id})
                              when
                              (inclusive == true and
                                    (storedValue == "all" or storedValue == value))
                                or (inclusive == false and storedValue != value)
                              ->
                           id
                 end)))
    excluded = MapSet.new(ETS.select(etsStore,
                 ETS.fun2ms(fn({{inclusive, storedValue}, id})
                              when
                              inclusive == false and storedValue == value
                              ->
                           id
                 end)))
    MapSet.difference(included, excluded)
  end
end