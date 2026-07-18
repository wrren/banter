ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Banter.Repo, :manual)

# Global scripted fakes used by non-async tests
{:ok, _} = Banter.LLM.Mock.start()
{:ok, _} = Banter.Tools.MockTool.start()
