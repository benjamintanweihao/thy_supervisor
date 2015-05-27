defmodule ThySupervisor do

  #######
  # API #
  #######

  def start_link(child_spec_list) do
    spawn_link(__MODULE__, :init, [child_spec_list])
  end

  def start_child(supervisor, {mod, fun, args}) do
    supervisor |> send({:start_child, {mod, fun, args}})
  end

  def restart_child(supervisor, pid) when is_pid(pid) do
    supervisor |> send({:restart_child, pid})
  end

  def terminate_child(supervisor, pid) when is_pid(pid) do
    supervisor |> send({:terminate_child, pid})
  end

  def which_children(supervisor) do
    supervisor |> send({:which_children, self})
  end

  def count_children(supervisor) do
    supervisor |> send({:count_children, self})
  end

  #####################
  # Private Functions #
  #####################

  def init(child_spec_list) do
    Process.flag(:trap_exit, true)
    child_spec_list |> start_children |> loop
  end

  def start_children(child_spec_list) do
    start_children(child_spec_list, HashDict.new)
  end

  # NOTE: We assume that the child calls start_link, otherwise there's no point.
  def start_children([{mod, fun, args}|rest], state) do
    new_state = HashDict.put(state, start_child({mod, fun, args}))
    start_children(rest, new_state)
  end

  def start_children([], state) do
    state
  end

  def start_child({mod, fun, args}) do
    {:ok, pid} = apply(mod, fun, args)
    {pid, {mod, fun, args}}
  end

  def terminate_child(pid) do
    Process.unlink(pid)
    Process.exit(pid, :kill)
    pid
  end

  def loop(state) do
    receive do
      {:start_child, {mod, fun, args}} ->
        new_state = state |> HashDict.put(start_child({mod, args, fun}))

        loop(new_state)

      {:restart_child, old_pid} ->
        {:ok, child_spec} = HashDict.fetch(state, old_pid)

        new_state = state
                      |> HashDict.delete(terminate_child(old_pid))
                      |> HashDict.put(start_child(child_spec))

        loop(new_state)

      {:terminate_child, pid} ->
        new_state = HashDict.delete(terminate_child(pid))

        loop(new_state)

      {:which_children, from} ->
        send(from, state)

        loop(state)

      {:count_children, from} ->
        send(from, state |> HashDict.count)

        loop(state)

      {:EXIT, from, :normal} ->
        new_state = HashDict.delete(state, from)

        loop(new_state)

      {:EXIT, from, _reason} ->
        {:ok, child_spec} = HashDict.fetch(state, from)
        Process.unlink(from)
        new_state = state
                      |> HashDict.delete(from)
                      |> HashDict.put(start_child(child_spec))

        loop(new_state)

      _ ->
        loop(state)

    end
  end

end
