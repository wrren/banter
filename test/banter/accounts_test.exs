defmodule Banter.AccountsTest do
  use Banter.DataCase, async: true

  alias Banter.{Accounts, Repo}
  alias Banter.Accounts.{User, UserToken}

  import Banter.TestFixtures

  describe "register_user/1" do
    test "creates a user with a hashed password" do
      assert {:ok, %User{} = user} =
               Accounts.register_user(%{
                 username: "some_user",
                 password: "a very secret password"
               })

      assert user.username == "some_user"
      assert is_binary(user.hashed_password)
      assert user.hashed_password != "a very secret password"
      refute Map.has_key?(user, :password) && user.password
    end

    test "validates username format and length" do
      for bad_username <- ["ab", String.duplicate("a", 31), "has space", "bang!"] do
        assert {:error, changeset} =
                 Accounts.register_user(%{username: bad_username, password: valid_password()})

        assert errors_on(changeset)[:username]
      end
    end

    test "validates password length" do
      assert {:error, changeset} =
               Accounts.register_user(%{username: "someone", password: "short"})

      assert errors_on(changeset)[:password]
    end

    test "rejects duplicate usernames case-insensitively" do
      {:ok, _user} = Accounts.register_user(%{username: "Alice", password: valid_password()})

      assert {:error, changeset} =
               Accounts.register_user(%{username: "alice", password: valid_password()})

      assert errors_on(changeset)[:username]
    end
  end

  describe "get_user_by_username_and_password/2" do
    test "returns the user for valid credentials, regardless of case" do
      user = user_fixture(%{username: "MixedCase"})

      assert %User{id: id} =
               Accounts.get_user_by_username_and_password("mixedcase", valid_password())

      assert id == user.id
    end

    test "returns nil for a wrong password" do
      user_fixture(%{username: "someone"})

      assert is_nil(Accounts.get_user_by_username_and_password("someone", "wrong password"))
    end

    test "returns nil for an unknown username" do
      assert is_nil(Accounts.get_user_by_username_and_password("nobody", "some password"))
    end
  end

  describe "update_user_password/3" do
    test "changes the password with a valid current password" do
      user = user_fixture()

      assert {:ok, updated} =
               Accounts.update_user_password(user, valid_password(), %{
                 password: "a brand new password"
               })

      assert is_nil(Accounts.get_user_by_username_and_password(user.username, valid_password()))

      assert Accounts.get_user_by_username_and_password(user.username, "a brand new password").id ==
               updated.id
    end

    test "rejects an incorrect current password" do
      user = user_fixture()

      assert {:error, changeset} =
               Accounts.update_user_password(user, "wrong password", %{
                 password: "a brand new password"
               })

      assert errors_on(changeset)[:current_password]
      assert Accounts.get_user_by_username_and_password(user.username, valid_password())
    end

    test "validates the new password" do
      user = user_fixture()

      assert {:error, changeset} =
               Accounts.update_user_password(user, valid_password(), %{password: "short"})

      assert errors_on(changeset)[:password]
    end

    test "deletes the user's session tokens" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      assert {:ok, _} =
               Accounts.update_user_password(user, valid_password(), %{
                 password: "a brand new password"
               })

      assert :error = Accounts.fetch_user_by_session_token(token)
    end
  end

  describe "session tokens" do
    test "generate/fetch round-trips the user" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      assert {:ok, fetched} = Accounts.fetch_user_by_session_token(token)
      assert fetched.id == user.id
    end

    test "fetch rejects unknown tokens" do
      assert :error = Accounts.fetch_user_by_session_token("not a token")
    end

    test "fetch rejects expired tokens" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      {1, _} =
        Repo.update_all(UserToken, set: [inserted_at: ~U[2020-01-01 00:00:00Z]])

      assert :error = Accounts.fetch_user_by_session_token(token)
    end

    test "delete invalidates the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      assert :ok = Accounts.delete_user_session_token(token)
      assert :error = Accounts.fetch_user_by_session_token(token)
    end
  end
end
