defmodule ThySupervisor do

  #######
  # API #
  #######

  def start_link(child_spec_list) do
    case spawn_link(__MODULE__, :init, [child_spec_list]) do
      pid when is_pid(pid) ->
        {:ok, pid}
      _ ->
        :error
    end
  end

  def start_child(supervisor, child_spec) do
    supervisor |> send({:start_child, self, child_spec})
    receive do
      {:ok, pid}  ->
        {:ok, pid}
      _ ->
        :error
    end
  end

  def terminate_child(supervisor, pid) when is_pid(pid) do
    supervisor |> send({:terminate_child, self, pid})
    receive do
      :ok ->
        :ok
      _ ->
        :error
    end
  end

  def restart_child(pid, child_spec) when is_pid(pid) do
    case terminate_child(pid) do
      :ok ->
        case start_child(child_spec) do
          {:ok, new_pid} ->
            {:ok, {new_pid, child_spec}}
          :error ->
            :error
        end
      :error ->
        :error
    end
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
    child_spec_list |> start_children |> Enum.into(HashDict.new) |> loop
  end

  # NOTE: We assume that the child calls start_link, otherwise there's no point.
  def start_children([child_spec|rest]) do
    case start_child(child_spec) do
      {:ok, pid} ->
        [{pid, child_spec}|start_children(rest)]
      :error ->
        :error
    end
  end

  def start_children([]), do: []

  def start_child({mod, fun, args}) do
    case apply(mod, fun, args) do
      pid when is_pid(pid) ->
        {:ok, pid}
      _ ->
        :error
    end
  end

  def terminate_children([]) do
    :ok
  end

  def terminate_children(child_specs) do
    child_specs |> Enum.each(fn {pid, _} -> terminate_child(pid) end)
  end

  def terminate_child(pid) do
    Process.exit(pid, :kill)
    :ok
  end

  def loop(state) do
    receive do
      {:start_child, from, child_spec} ->
        case start_child(child_spec) do
          {:ok, pid} ->
            send(from, {:ok, pid})
            loop(state |> HashDict.put(pid, child_spec))
          :error ->
            send(from, :error)
            loop(state)
        end

      {:terminate_child, from, pid} ->
        case terminate_child(pid) do
          :ok ->
            send(from, :ok)
            loop(state |> HashDict.delete(pid))
          :error ->
            send(from, :error)
            loop(state)
        end

      {:restart_child, old_pid} ->
        case HashDict.fetch(state, old_pid) do
          {:ok, child_spec} ->
            case restart_child(old_pid, child_spec) do
              {:ok, {pid, child_spec}} ->
                state
                  |> HashDict.delete(old_pid)
                  |> HashDict.put(pid, child_spec)
                  |> loop
              :error ->
                loop(state)
            end
          x ->
            loop(state)
        end

      {:count_children, from} ->
        send(from, {:ok, HashDict.size(state)})
        loop(state)

      {:which_children, from} ->
        send(from, {:ok, state})
        loop(state)

      {:stop, from} ->
        terminate_children(state)
        send(from, :ok)

      {:EXIT, from, :normal} ->
        loop(state |> HashDict.delete(from))

      {:EXIT, from, :killed} ->
        loop(state |> HashDict.delete(from))

      {:EXIT, from, reason} ->
        send(self, {:restart_child, from})
        loop(state)
    end
  end
end
