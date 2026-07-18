defmodule BanterWeb.RegistrationLiveTest do
  use BanterWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Banter.TestFixtures

  test "renders the registration form", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/register")

    assert has_element?(view, "#registration-form")
    assert has_element?(view, "#registration-form input[name='user[username]']")
    assert has_element?(view, "#registration-form input[name='user[password]']")
    assert has_element?(view, "#register-button")
  end

  test "redirects to home when already authenticated", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/users/register")
  end

  test "validates input inline", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/register")

    html =
      view
      |> element("#registration-form")
      |> render_change(%{user: %{username: "ab", password: "short"}})

    assert html =~ "should be at least"
  end

  test "registers and logs in via the session controller", %{conn: conn} do
    username = unique_username()

    conn =
      post(conn, ~p"/users/register", %{
        "user" => %{"username" => username, "password" => valid_password()}
      })

    assert redirected_to(conn) == "/"
    assert get_session(conn, "user_token")

    # the session works
    {:ok, view, _html} = live(conn, ~p"/")
    assert render(view) =~ username
  end

  test "rejects invalid registration params", %{conn: conn} do
    conn =
      post(conn, ~p"/users/register", %{
        "user" => %{"username" => "x", "password" => "short"}
      })

    assert redirected_to(conn) == "/users/register"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Could not create account"
    refute get_session(conn, "user_token")
  end
end
