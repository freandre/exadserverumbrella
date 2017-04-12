defmodule ExAdServerTest do
  use AdServerCase, async: true
  
  test "That our adServer can load some basic data", context do
    {:ok, configserver} = ConfigServer.start_link({"./test/resources/simpleTargetingData.json", 0})
    {:ok, adserver} = ExAdServer.start_link(ConfigServer.getMetadata(configserver))

    Enum.each(context.simpleAdsData, &ExAdServer.loadAd(adserver, &1))
    Enum.each(context.simpleAdsData,
              fn(ad) ->
                returned = ExAdServer.getAd(adserver, ad["adid"])
                assert(returned == ad,
                      """
                      Ads are not identical
                      Expected:
                      #{inspect(ad)}
                      Had:
                      #{inspect(returned)}
                      """)
              end
            )
  end

  test "That our adServer can update some basic data", context do
    {:ok, configserver} = ConfigServer.start_link({"./test/resources/simpleTargetingData.json", 0})
    {:ok, adserver} = ExAdServer.start_link(ConfigServer.getMetadata(configserver))

    Enum.each(context.simpleAdsData, &ExAdServer.loadAd(adserver, &1))

    [ad | _] = context.simpleAdsData
    adMod = Map.put(ad, "test", "test")

    ExAdServer.loadAd(adserver, adMod)
    returned = ExAdServer.getAd(adserver, ad["adid"])

    assert(returned != ad,
          """
          Ads are identical
          Expected:
          #{inspect(adMod)}
          Had:
          #{inspect(returned)}
          """)
  end

  test "That our adServer returns :notfound", context do
    {:ok, configserver} = ConfigServer.start_link({"./test/resources/simpleTargetingData.json", 0})
    {:ok, adserver} = ExAdServer.start_link(ConfigServer.getMetadata(configserver))

    Enum.each(context.simpleAdsData, &ExAdServer.loadAd(adserver, &1))

    returned = ExAdServer.getAd(adserver, 42)

    assert(returned == :notfound,
          """
          Unable to handle :notfound
          Expected:
          :notfound
          Had:
          #{inspect(returned)}
          """)
  end

  test "That our adServer filter ads properly", context do
    {:ok, configserver} = ConfigServer.start_link({"./test/resources/simpleTargetingData.json", 0})
    {:ok, adserver} = ExAdServer.start_link(ConfigServer.getMetadata(configserver))

    Enum.each(context.simpleAdsData, &ExAdServer.loadAd(adserver, &1))

    Enum.each(context.adsFilterData,
              fn(%{"request" => request, "expected" => expected}) ->
                  returned = ExAdServer.filterAd(adserver, request)
                  assert(returned == MapSet.new(expected),
                        """
                        Unable to handle filtering on request
                        #{inspect(request)}
                        Expected:
                        #{inspect(expected)}
                        Had:
                        #{inspect(returned)}
                        """)
              end)
  end
end