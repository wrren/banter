defmodule Banter.Crypto do
  @moduledoc """
  Crypto utilities for encrypting and decrypting sensitive data like API keys.
  Uses AES-256-CBC with PKCS7 padding.
  """

  @cipher :aes_256_cbc
  @iv_len 16
  @key_len 32

  @doc """
  Encrypts plaintext using AES-256-CBC.
  Returns Base64-encoded ciphertext with prepended IV.
  """
  @spec encrypt(binary()) :: binary()
  def encrypt(plaintext) when is_binary(plaintext) do
    key = get_key()
    iv = :crypto.strong_rand_bytes(@iv_len)

    ciphertext =
      :crypto.crypto_one_time(@cipher, key, iv, pad(plaintext), true)

    Base.encode64(iv <> ciphertext)
  end

  @doc """
  Decrypts Base64-encoded ciphertext.
  """
  @spec decrypt(binary()) :: binary()
  def decrypt(ciphertext) when is_binary(ciphertext) do
    key = get_key()

    case Base.decode64(ciphertext) do
      {:ok, <<iv::binary-size(@iv_len), ciphertext::binary>>} ->
        :crypto.crypto_one_time(@cipher, key, iv, ciphertext, false)
        |> unpad()

      :error ->
        raise ArgumentError, "invalid Base64 encoding"
    end
  end

  defp get_key do
    case Application.get_env(:banter, :api_key_encryption_key) do
      key when is_binary(key) and byte_size(key) >= @key_len ->
        binary_part(key, 0, @key_len)

      key when is_binary(key) ->
        :crypto.hash(:sha256, key)

      nil ->
        raise ArgumentError, "api_key_encryption_key not configured"
    end
  end

  defp pad(data) do
    padding = @iv_len - rem(byte_size(data), @iv_len)
    data <> :binary.copy(<<padding>>, padding)
  end

  defp unpad(data) do
    data_size = byte_size(data)
    pad_size = :binary.last(data)
    content_size = data_size - pad_size

    <<content::binary-size(^content_size), _padding::binary-size(^pad_size)>> = data

    content
  end
end
