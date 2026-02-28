defmodule PklElixir.BinaryDecoder do
  @moduledoc false

  # Pkl-binary type codes
  @object 0x01
  @map 0x02
  @mapping 0x03
  @list 0x04
  @listing 0x05
  @set 0x06
  @duration 0x07
  @data_size 0x08
  @pair 0x09
  @int_seq 0x0A
  @regex 0x0B
  # 0x0C class, 0x0D typealias, 0x0E function — not meaningful to decode
  # 0x0F bytes

  # Object member codes
  @property 0x10
  @entry 0x11
  @element 0x12

  @doc """
  Decode pkl-binary bytes (msgpack-encoded) into Elixir terms.

  Returns `{:ok, value}` or `{:error, reason}`.
  """
  def decode(nil), do: {:ok, nil}
  def decode(<<>>), do: {:ok, nil}

  def decode(bytes) when is_binary(bytes) do
    case Msgpax.unpack(bytes) do
      {:ok, term} -> {:ok, decode_value(term)}
      {:error, _} = err -> err
    end
  end

  # Primitives
  defp decode_value(v) when is_binary(v), do: v
  defp decode_value(v) when is_integer(v), do: v
  defp decode_value(v) when is_float(v), do: v
  defp decode_value(true), do: true
  defp decode_value(false), do: false
  defp decode_value(nil), do: nil

  # Object → map of properties
  # Structure: [0x01, class_name, module_uri, [member1, member2, ...]]
  defp decode_value([@object, _class, _uri, members]) when is_list(members) do
    decode_members(members)
  end

  # Map / Mapping → Elixir map
  defp decode_value([@map, map_data]) when is_map(map_data) do
    decode_map(map_data)
  end

  defp decode_value([@mapping, map_data]) when is_map(map_data) do
    decode_map(map_data)
  end

  # List / Listing → Elixir list
  defp decode_value([@list, elements]) when is_list(elements) do
    Enum.map(elements, &decode_value/1)
  end

  defp decode_value([@listing, elements]) when is_list(elements) do
    Enum.map(elements, &decode_value/1)
  end

  # Set → MapSet
  defp decode_value([@set, elements]) when is_list(elements) do
    elements |> Enum.map(&decode_value/1) |> MapSet.new()
  end

  # Duration → %{value, unit}
  defp decode_value([@duration, value, unit]) do
    %{value: value, unit: unit}
  end

  # DataSize → %{value, unit}
  defp decode_value([@data_size, value, unit]) do
    %{value: value, unit: unit}
  end

  # Pair → two-element tuple
  defp decode_value([@pair, first, second]) do
    {decode_value(first), decode_value(second)}
  end

  # IntSeq → Range (when step=1) or struct
  defp decode_value([@int_seq, start_val, end_val, 1]) do
    start_val..end_val
  end

  defp decode_value([@int_seq, start_val, end_val, step]) do
    start_val..end_val//step
  end

  # Regex → compiled Regex
  defp decode_value([@regex, pattern]) do
    Regex.compile!(pattern)
  end

  # Fallback: return raw term
  defp decode_value(other), do: other

  defp decode_members(members) do
    Enum.reduce(members, %{}, fn
      [@property, name, value], acc ->
        Map.put(acc, name, decode_value(value))

      [@entry, key, value], acc ->
        Map.put(acc, decode_value(key), decode_value(value))

      [@element, value], acc ->
        idx = Map.get(acc, :__elements_count__, 0)
        acc
        |> Map.put(idx, decode_value(value))
        |> Map.put(:__elements_count__, idx + 1)

      _unknown, acc ->
        acc
    end)
    |> Map.delete(:__elements_count__)
  end

  defp decode_map(map_data) do
    Map.new(map_data, fn {k, v} -> {decode_value(k), decode_value(v)} end)
  end
end
