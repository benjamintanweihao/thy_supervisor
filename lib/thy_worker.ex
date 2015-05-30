defmodule ThyWorker do
  def start_link do
    spawn_link(fn -> loop end)
  end

  def loop do
    receive do
      :stop -> :ok

      :crash -> 1 / 0

      msg ->
        IO.inspect msg
        loop
    end
  end
end
