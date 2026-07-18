defmodule BanterWeb.LoginLiveTest do
  use BanterWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Banter.TestFixtures

  test "renders the login form", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/log-in")

    assert has_element?(view, "#login-form")
    assert has_element?(view, "#login-form input[name='user[username]']")
    assert has_element?(view, "#login-form input[name='user[password]']")
    assert has_element?(view, "#login-button")
  end

  test "redirects to home when already authenticated", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/users/log-in")
  end

  test "logs in with valid credentials", %{conn: conn} do
    user = user_fixture()

    conn =
      post(conn, ~p"/users/log-in", %{
        "user" => %{"username" => user.username, "password" => valid_password()}
      })

    assert redirected_to(conn) == "/"
    assert get_session(conn, "user_token")
  end

  test "rejects invalid credentials with a generic error" do
    user = user_fixture()

    for params <- [
          %{"username" => user.username, "password" => "wrong password"},
          %{"username" => "no_such_user", "password" => valid_password()}
        ] do
      conn =
        post(build_conn(), ~p"/users/log-in", %{"user" => params})

      assert redirected_to(conn) == "/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid username or password"
      refute get_session(conn, "user_token")
    end
  end

  test "logs out", %{conn: conn} do
    user = user_fixture()
    conn = log_in_user(conn, user)

    conn = delete(conn, ~p"/users/log-out")

    assert redirected_to(conn) == "/users/log-in"
    refute get_session(conn, "user_token")

    # the old session token no longer works
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/")
  end
end
