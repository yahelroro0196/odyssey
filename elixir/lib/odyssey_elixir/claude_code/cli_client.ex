defmodule OdysseyElixir.ClaudeCode.CliClient do
  @moduledoc """
  Agent backend that spawns the Claude Code CLI per turn with `--output-format stream-json`.
  Uses `--resume` for multi-turn conversation continuity.
  """

  @behaviour OdysseyElixir.AgentBackend

  require Logger
  alias OdysseyElixir.{Codex.AppServer, Config, SSH}

  @port_line_bytes 1_048_576
  @max_stream_log_bytes 1_000

  @type session :: %{
          workspace: Path.t(),
          worker_host: String.t() | nil,
          role: :coder | :review,
          resume_session_id: String.t() | nil,
          config: map()
        }

  @spec start_session(Path.t(), keyword()) :: {:ok, session()} | {:error, term()}
  def start_session(workspace, opts \\ []) do
    worker_host = Keyword.get(opts, :worker_host)
    role = Keyword.get(opts, :role, :coder)
    agent_config = Config.agent_codex_config(role)

    with {:ok, expanded_workspace} <- AppServer.validate_workspace_cwd(workspace, worker_host) do
      {:ok,
       %{
         workspace: expanded_workspace,
         worker_host: worker_host,
         role: role,
         resume_session_id: nil,
         config: agent_config
       }}
    end
  end

  @max_inline_prompt_bytes 512_000

  @spec run_turn(session(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_turn(session, prompt, issue, opts \\ []) do
    on_message = Keyword.get(opts, :on_message, &default_on_message/1)

    if byte_size(prompt) > @max_inline_prompt_bytes do
      run_turn_with_prompt_file(session, prompt, issue, on_message)
    else
      run_turn_inline(session, prompt, issue, on_message)
    end
  end

  defp run_turn_inline(session, prompt, issue, on_message) do
    command = build_command(session, shell_escape(prompt))
    do_run_turn(session, command, issue, on_message)
  end

  defp run_turn_with_prompt_file(session, prompt, issue, on_message) do
    prompt_file = Path.join(session.workspace, ".odyssey_prompt_#{:erlang.unique_integer([:positive])}")
    File.write!(prompt_file, prompt)

    try do
      command = build_command(session, "\"$(cat #{shell_escape(prompt_file)})\"")
      do_run_turn(session, command, issue, on_message)
    after
      File.rm(prompt_file)
    end
  end

  defp do_run_turn(session, command, issue, on_message) do
    case start_port(session.workspace, session.worker_host, command) do
      {:ok, port} ->
        metadata = port_metadata(port, session.worker_host)
        session_id = session.resume_session_id || "claude-#{:erlang.unique_integer([:positive])}"

        emit_message(on_message, :session_started, %{session_id: session_id}, metadata)

        Logger.info("Claude Code session started for #{issue_context(issue)} session_id=#{session_id}")

        timeout_ms = session.config.turn_timeout_ms

        case receive_loop(port, on_message, timeout_ms, "", false) do
          {:ok, result} ->
            new_session_id = Map.get(result, :session_id, session_id)

            Logger.info("Claude Code session completed for #{issue_context(issue)} session_id=#{new_session_id}")

            {:ok,
             %{
               result: :turn_completed,
               session_id: new_session_id,
               resume_session_id: new_session_id,
               usage: Map.get(result, :usage, %{})
             }}

          {:error, reason} ->
            Logger.warning("Claude Code session ended with error for #{issue_context(issue)}: #{inspect(reason)}")

            emit_message(on_message, :turn_ended_with_error, %{session_id: session_id, reason: reason}, metadata)

            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Claude Code failed to start for #{issue_context(issue)}: #{inspect(reason)}")
        emit_message(on_message, :startup_failed, %{reason: reason}, %{})
        {:error, reason}
    end
  end

  @spec stop_session(session()) :: :ok
  def stop_session(_session), do: :ok

  defp build_command(session, prompt_arg) do
    base_command = session.config.command || "claude"
    cc_opts = session.config.claude_code_options || %{}

    args =
      [base_command, "-p", prompt_arg, "--output-format", "stream-json"] ++
        permission_args(cc_opts) ++
        model_args(cc_opts) ++
        max_turns_args(cc_opts) ++
        resume_args(session.resume_session_id) ++
        append_system_prompt_args(cc_opts) ++
        mcp_config_args(cc_opts)

    Enum.join(args, " ")
  end

  defp permission_args(cc_opts) do
    case map_string_key(cc_opts, "permission_mode") do
      mode when is_binary(mode) -> ["--permission-mode", mode]
      _ -> ["--dangerously-skip-permissions"]
    end
  end

  defp model_args(cc_opts) do
    case map_string_key(cc_opts, "model") do
      model when is_binary(model) -> ["--model", model]
      _ -> []
    end
  end

  defp max_turns_args(cc_opts) do
    case map_string_key(cc_opts, "max_turns_per_invocation") do
      n when is_integer(n) -> ["--max-turns", to_string(n)]
      _ -> []
    end
  end

  defp resume_args(nil), do: []
  defp resume_args(session_id) when is_binary(session_id), do: ["--resume", shell_escape(session_id)]

  defp append_system_prompt_args(cc_opts) do
    case map_string_key(cc_opts, "append_system_prompt") do
      text when is_binary(text) -> ["--append-system-prompt", shell_escape(text)]
      _ -> []
    end
  end

  defp mcp_config_args(cc_opts) do
    case map_string_key(cc_opts, "mcp_config") do
      path when is_binary(path) -> ["--mcp-config", shell_escape(path)]
      _ -> []
    end
  end

  defp start_port(workspace, nil, command) do
    executable = System.find_executable("bash")

    if is_nil(executable) do
      {:error, :bash_not_found}
    else
      port =
        Port.open(
          {:spawn_executable, String.to_charlist(executable)},
          [
            :binary,
            :exit_status,
            :stderr_to_stdout,
            args: [~c"-lc", String.to_charlist(command)],
            cd: String.to_charlist(workspace),
            line: @port_line_bytes
          ]
        )

      {:ok, port}
    end
  end

  defp start_port(workspace, worker_host, command) when is_binary(worker_host) do
    remote_command = "cd #{shell_escape(workspace)} && exec #{command}"
    SSH.start_port(worker_host, remote_command, line: @port_line_bytes)
  end

  defp receive_loop(port, on_message, timeout_ms, pending_line, seen_first_system) do
    receive do
      {^port, {:data, {:eol, chunk}}} ->
        complete_line = pending_line <> to_string(chunk)
        handle_line(port, on_message, complete_line, timeout_ms, seen_first_system)

      {^port, {:data, {:noeol, chunk}}} ->
        receive_loop(port, on_message, timeout_ms, pending_line <> to_string(chunk), seen_first_system)

      {^port, {:exit_status, 0}} ->
        {:error, :process_exited_without_result}

      {^port, {:exit_status, status}} ->
        {:error, {:port_exit, status}}
    after
      timeout_ms ->
        {:error, :turn_timeout}
    end
  end

  defp handle_line(port, on_message, data, timeout_ms, seen_first_system) do
    case Jason.decode(data) do
      {:ok, %{"type" => "result"} = payload} ->
        usage = extract_usage(payload)
        session_id = Map.get(payload, "session_id")

        emit_message(on_message, :turn_completed, %{payload: payload, raw: data}, %{usage: usage})

        {:ok, %{session_id: session_id, usage: usage}}

      {:ok, %{"type" => "system"} = payload} ->
        if seen_first_system do
          emit_message(on_message, :notification, %{payload: payload, raw: data}, %{})
        end

        receive_loop(port, on_message, timeout_ms, "", true)

      {:ok, %{"type" => type} = payload} when type in ["assistant", "tool_use", "tool_result"] ->
        emit_message(on_message, :notification, %{payload: payload, raw: data}, usage_metadata(payload))
        receive_loop(port, on_message, timeout_ms, "", seen_first_system)

      {:ok, payload} ->
        emit_message(on_message, :notification, %{payload: payload, raw: data}, usage_metadata(payload))
        receive_loop(port, on_message, timeout_ms, "", seen_first_system)

      {:error, _} ->
        log_non_json_line(data)
        receive_loop(port, on_message, timeout_ms, "", seen_first_system)
    end
  end

  defp extract_usage(payload) do
    case Map.get(payload, "usage") do
      %{} = usage -> usage
      _ -> %{}
    end
  end

  defp usage_metadata(payload) do
    case extract_usage(payload) do
      empty when map_size(empty) == 0 -> %{}
      usage -> %{usage: usage}
    end
  end

  defp emit_message(on_message, event, details, metadata) when is_function(on_message, 1) do
    message = metadata |> Map.merge(details) |> Map.put(:event, event) |> Map.put(:timestamp, DateTime.utc_now())
    on_message.(message)
  end

  defp port_metadata(port, worker_host) when is_port(port) do
    base =
      case :erlang.port_info(port, :os_pid) do
        {:os_pid, os_pid} -> %{agent_pid: to_string(os_pid)}
        _ -> %{}
      end

    case worker_host do
      host when is_binary(host) -> Map.put(base, :worker_host, host)
      _ -> base
    end
  end

  defp log_non_json_line(data) do
    text =
      data
      |> to_string()
      |> String.trim()
      |> String.slice(0, @max_stream_log_bytes)

    if text != "" do
      if String.match?(text, ~r/\b(error|warn|warning|failed|fatal|panic|exception)\b/i) do
        Logger.warning("Claude Code stream output: #{text}")
      else
        Logger.debug("Claude Code stream output: #{text}")
      end
    end
  end

  defp issue_context(%{id: issue_id, identifier: identifier}) do
    "issue_id=#{issue_id} issue_identifier=#{identifier}"
  end

  defp shell_escape(value) when is_binary(value) do
    "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
  end

  defp map_string_key(map, key) when is_map(map), do: Map.get(map, key)
  defp map_string_key(_map, _key), do: nil

  defp default_on_message(_message), do: :ok
end
