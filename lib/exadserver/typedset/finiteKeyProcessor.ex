defmodule ExAdServer.TypedSet.FiniteKeyProcessor do
  @moduledoc """
  Finite key processor implementation.
  """
  @compile {:parse_transform, :ms_transform}

  @behaviour ExAdServer.Bitmap.BehaviorKeysProcessor

  import ExAdServer.Utils.BitUtils
  import ExAdServer.Utils.Storage
  alias :ets, as: ETS

  ## Behaviour Callbacks
  def generateAndStoreIndex({adConf, bitIndex}, {indexName, indexMetadata}, indexes) do
    {store, indexes} = getStore(indexName, indexes)
    distinct_values = indexMetadata["distinctvalues"]
    values_to_store = adConf["targeting"][indexName]
                      |> getValuesToStore(distinct_values)

    Enum.each(distinct_values,
            &(generateAndStoreValue(store, &1, values_to_store, bitIndex)))

    indexes
  end

  def findInIndex(request, {indexName, _}, indexes) do
    {store, _indexes} = getStore(indexName, indexes)

    value = getValue(request[indexName])
    [{^value, data}] = ETS.lookup(store, value)
    val = decodebitField(data)
    IO.puts(inspect(val))
    val
  end

  ## Private functions

  ## Select matching value to store data depending on conf values and inclusive tag
  defp getValuesToStore(confValues, distinctValues) do
    inclusive = confValues["inclusive"]
    cond do
      inclusive == nil -> ["unknown" | distinctValues]
      inclusive and confValues["data"] == ["all"] -> ["unknown" | distinctValues]
      inclusive == false and confValues["data"] == ["all"] -> ["unknown"]
      inclusive -> confValues["data"]
      inclusive == false -> distinctValues -- confValues["data"]
    end
  end

  ## Given a key of distinct values, check if it's part of values to store
  ## set the bit of retrived bitmap at index
  defp generateAndStoreValue(store, distinctvalue, keysToStore, bitIndex) do
    data = getStoredValue(store, distinctvalue)
           |> setBitAt(distinctvalue in keysToStore, bitIndex)
    dumpBits(data)
    ETS.insert(store, {distinctvalue,  data})
  end

  ## Get a stored value or initialize it
  defp getStoredValue(store, id) do
    data = ETS.lookup(store, id)

    if data == [] do
      {0, 0}
    else
      elem(Enum.at(data, 0), 1)
    end
  end

  ## Simple filter to handle unknown value
  defp getValue(requestValue) do
    if requestValue == nil do
      "unknown"
    else
      requestValue
    end
  end

  ## Decode a bitfield to a list of index having bit set to 1
  defp decodebitField({_, size} = data) do
    decodebitField(data, size - 1, MapSet.new)
  end

  defp decodebitField(data, index, ret) when index >= 0 do
    bit = getBitAt(data, index)
    decodebitField(data, index - 1, updateRet(ret, bit, index))
  end

  defp decodebitField(_, index, ret) when index < 0 do
    ret
  end

  ## Update list of index according to bit
  defp updateRet(ret, bit, index) do
    if bit do
      MapSet.put(ret,index)
    else
      ret
    end
  end
end
