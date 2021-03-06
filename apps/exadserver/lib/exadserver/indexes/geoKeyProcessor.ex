defmodule ExAdServer.Indexes.GeoKeyProcessor do
  @moduledoc """
  Geo key processor implementation.
  """

  @behaviour ExAdServer.Indexes.BehaviorKeysProcessor

  require Logger
  import ExAdServer.Utils.Storage
  alias :ets, as: ETS

  ## Sorted array giving for a bit precision the approximation radius in meters of geohash
  @bitresolution [{52, 0.5971},
                  {50, 1.1943},
                  {48, 2.3889},
                  {46, 4.7774},
                  {44, 9.5547},
                  {42, 19.1095},
                  {40, 38.2189},
                  {38, 76.4378},
                  {36, 152.8757},
                  {34, 305.751},
                  {32, 611.5028},
                  {30, 1_223.0056},
                  {28, 2_446.0112},
                  {26, 4_892.0224},
                  {24, 9_784.0449},
                  {22, 19_568.0898},
                  {20, 39_136.1797},
                  {18, 78_272.35938},
                  {16, 156_544.7188},
                  {14, 313_089.4375},
                  {12, 626_178.875},
                  {10, 1_252_357.75},
                  {8, 2_504_715.5},
                  {6, 5_009_431},
                  {4, 10_018_863}]

  ## Behaviour Callbacks

  def generateMetadata(targeterMetada) do
    ret = targeterMetada
    |> Enum.filter_map(fn ({_, v}) -> v["type"] == "geo" end,
                       fn ({k, v}) ->
                         createStore(getIxAtom(k))
                         {k, ExAdServer.Indexes.GeoKeyProcessor, v}
                       end)
    Logger.debug fn -> "[GeoKeyProcessor] - Exiting generateMetadata returning:\n
                        #{inspect(ret)}" end
    ret
  end

  def generateAndStoreIndex({adConf, _}, {indexName, _}) do
    geo_targets = getGeoTargets(adConf["targeting"][indexName]["data"])
    inclusive = adConf["targeting"][indexName]["inclusive"]

    Logger.debug "[GeoKeyProcessor] - generateAndStoreIndex processing:"
    Logger.debug fn -> "> inclusive: #{inspect(inclusive)}" end
    Logger.debug fn -> "> #{inspect(geo_targets)}" end

    ret = geo_targets
    |> Enum.map(fn(geo_target) ->
                  hash = Geohash.encode(geo_target["latitude"], geo_target["longitude"], geo_target["precision"])
                  {geo_target["precision"], [hash | hash
                                                    |> Geohash.neighbors
                                                    |> Enum.map(fn ({_, key}) -> key end)]}
                end)

    Logger.debug fn -> "> generated hash list: #{inspect(ret)}" end

    ETS.insert(getIxAtom(indexName), {adConf["adid"], {inclusive, ret}})
  end

  def findInIndex(adRequest, {indexName, _}, accumulator) do
    Logger.debug fn -> "[GeoKeyProcessor] - findInIndex request #{indexName}:\n#{inspect(accumulator)}" end

    hash = getGeoHash(adRequest["geo"], computeResolution(64))

    ret = Enum.reduce(accumulator, [],
                fn(ad_id, cfg_list) ->
                  [{^ad_id, {inclusive, geo_list}}] =
                              ETS.lookup(getIxAtom(indexName), ad_id)

                  is_in = Enum.reduce_while(geo_list, false,
                                               fn(data, _) ->
                                                 hash
                                                 |> findInUniqueGeoList(inclusive, data)
                                                 |> build_return
                                               end)
                  if is_in do
                    [ad_id | cfg_list]
                  else
                    cfg_list
                  end
                end)

    Logger.debug fn -> "[GeoKeyProcessor] - findInIndex exit:\n#{inspect(ret)}" end

    ret
  end

  def cleanup(indexName, _) do
    deleteStore(getIxAtom(indexName))
  end

  ## Private functions

  ## Create a list of geotargets to deal with
  defp getGeoTargets(geotargets), do: Enum.map(geotargets, &getGeoTarget/1)

  ## Create a map with latitude, longitude, precision
  defp getGeoTarget("all") do
    %{"latitude" => 0,
    "longitude" => 0,
    "precision" => 1}
  end
  defp getGeoTarget(geotarget) do
    %{"latitude" => geotarget["latitude"],
    "longitude" => geotarget["longitude"],
    "precision" => getResolution(geotarget["radius"])}
  end

  ## Find the immediate upper resolution based on radius
  ## if no radius is given, the whole planet is the target
  defp getResolution(nil), do: 1 # return the biggest value
  defp getResolution(radius), do: parseResolutionList(@bitresolution, radius)

  ## Geohash library approximate the nbits by doing precision * 5
  defp computeResolution(nbBits), do: round(nbBits / 5)

  ## Recursively parse precision array
  defp parseResolutionList([val | remaining], radius) do
    if elem(val, 1) > radius do
      computeResolution(elem(val, 0))
    else
      parseResolutionList(remaining, radius)
    end
  end

  ## Check that a location is in a configuration list
  defp findInUniqueGeoList(hash, inclusive, {precision, geo_list}) do
    <<reduced_hash::binary-size(precision), _::binary>> = hash
    Logger.debug fn -> "[GeoKeyProcessor] - findInUniqueGeoList geo #{inspect(hash)}:\n#{inspect(reduced_hash)}\nin list:#{inspect(geo_list)}" end
    cond do
      inclusive and reduced_hash in geo_list
          -> true
      inclusive != true and (reduced_hash in geo_list) != true
          -> true
      true -> false
    end
  end

  ## Get a list of geohash to look for
  defp getGeoHash(nil, _), do: getGeoHash(0, 0, 1)
  defp getGeoHash(data, precision), do: getGeoHash(data["latitude"], data["longitude"], precision)
  defp getGeoHash(lat, long, precision) do
      Geohash.encode(lat, long, precision)
  end

  ## Build the response based on the searching result
  defp build_return(true), do: {:halt, true}
  defp build_return(is_in), do: {:cont, is_in}
end
