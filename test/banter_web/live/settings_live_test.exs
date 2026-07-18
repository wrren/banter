defmodule BanterWeb.SettingsLiveTest do
  use BanterWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Banter.TestFixtures

  alias Banter.Accounts

  setup :register_and_log_in_user

  test "renders the password change form", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/users/settings")

    assert has_element?(view, "#password-form")
    assert has_element?(view, "#password-form input[name='user[current_password]']")
    assert has_element?(view, "#password-form input[name='user[password]']")
    assert has_element?(view, "#password-form input[name='user[password_confirmation]']")
    assert render(view) =~ user.username
  end

  test "validates the new password inline", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/users/settings")

    html =
      view
      |> element("#password-form")
      |> render_change(%{
        user: %{current_password: "x", password: "short", password_confirmation: "short"}
      })

    assert html =~ "should be at least"
  end

  test "changes the password and redirects to login", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/users/settings")

    view
    |> element("#password-form")
    |> render_submit(%{
      user: %{
        current_password: valid_password(),
        password: "a brand new password",
        password_confirmation: "a brand new password"
      }
    })

    assert_redirect(view, "/users/log-in")

    # old password no longer works, new one does
    assert is_nil(Accounts.get_user_by_username_and_password(user.username, valid_password()))

    assert Accounts.get_user_by_username_and_password(user.username, "a brand new password")
  end

  test "rejects a wrong current password", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/users/settings")

    html =
      view
      |> element("#password-form")
      |> render_submit(%{
        user: %{
          current_password: "wrong password",
          password: "a brand new password",
          password_confirmation: "a brand new password"
        }
      })

    assert html =~ "is not correct"
    assert Accounts.get_user_by_username_and_password(user.username, valid_password())
  end

  test "rejects mismatched confirmation", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/users/settings")

    html =
      view
      |> element("#password-form")
      |> render_submit(%{
        user: %{
          current_password: valid_password(),
          password: "a brand new password",
          password_confirmation: "does not match"
        }
      })

    assert html =~ "does not match password"
    assert Accounts.get_user_by_username_and_password(user.username, valid_password())
  end
end
