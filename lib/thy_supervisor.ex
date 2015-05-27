defmodule ThySupervisor do

  #######
  # API #
  #######

  def start_link(child_spec_list) do
    spawn_link(__MODULE__, :init, [child_spec_list])
  end

  # TODO: Should this be synchronous?
  def start_child(supervisor, {mod, fun, args}) do
    supervisor |> send({:start_child, {mod, fun, args}})
  end

  def terminate_child(supervisor, pid) when is_pid(pid) do
    supervisor |> send({:terminate_child, pid})
  end

  def count_children(supervisor) do
    supervisor |> send({:count_children, self})
    receive do
      {:ok, count} -> count
       _ -> :ok
    end
  end

  def which_children(supervisor) do
    supervisor |> send({:which_children, self})
    receive do
      {:ok, children} -> children
       _ -> :ok
    end
  end

  def stop(supervisor) do
    supervisor |> send({:stop, self})
    receive do
      :ok -> :ok
    end
  end

  #####################
  # Private Functions #
  #####################

  def init(child_spec_list) do
    Process.flag(:trap_exit, true)
    child_spec_list |> start_children |> loop
  end

  def start_child({mod, fun, args}) do
    pid = apply(mod, fun, args)
    HashDict.new |> HashDict.put(pid, {mod, fun, args})
  end

  def start_children(child_spec_list) do
    start_children(child_spec_list, HashDict.new)
  end

  # NOTE: We assume that the child calls start_link, otherwise there's no point.
  def start_children([child_spec|rest], state) do
    new_state = state |> HashDict.merge(start_child(child_spec))
    start_children(rest, new_state)
  end

  def start_children([], state) do
    state
  end

  def terminate_child(pid) do
    Process.exit(pid, :kill)
    pid
  end

  def terminate_children([]) do
    :ok
  end

  def terminate_children([child|children]) do
    terminate_child(child)
    terminate_children(children)
  end

  def loop(state) do
    receive do

      {:start_child, child_spec} ->
        new_state = state |> HashDict.merge(start_child(child_spec))
        loop(new_state)

      {:restart_child, old_pid} ->
        case HashDict.fetch(state, old_pid) do
          {:ok, child_spec} ->

          new_state = state
                        |> HashDict.delete(terminate_child(old_pid))
                        |> HashDict.merge(start_child(child_spec))

          loop(new_state)

          _ ->
            loop(state)

        end

      {:terminate_child, pid} ->
        new_state = state |> HashDict.delete(terminate_child(pid))
        loop(new_state)

      {:count_children, from} ->
        send(from, {:ok, state |> HashDict.size})
        loop(state)

      {:which_children, from} ->
        send(from, {:ok, state})
        loop(state)

      {:stop, from} ->
        terminate_children(state |> HashDict.keys)
        send(from, :ok)

      {:EXIT, from, :normal} ->
        new_state = HashDict.delete(state, from)

        loop(new_state)

      {:EXIT, from, _reason} ->
        case HashDict.fetch(state, from) do
          {:ok, child_spec} ->
            new_state = state
                          |> HashDict.delete(from)
                          |> HashDict.merge(start_child(child_spec))

            loop(new_state)

          _ ->
            loop(state)
        end

      _ ->
        loop(state)

    end
  end

end
