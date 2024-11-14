defimpl FunWithFlags.Actor, for: Todoplace.Accounts.User do
  def id(%{email: email}) do
    "user:#{email}"
  end
end
