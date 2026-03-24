defmodule OdysseyElixir.Config do
  @moduledoc """
  Runtime configuration loaded from `WORKFLOW.md`.
  """

  alias OdysseyElixir.Config.Schema
  alias OdysseyElixir.Workflow

  @default_prompt_template """
  You are working on a Linear issue.

  Identifier: {{ issue.identifier }}
  Title: {{ issue.title }}

  Body:
  {% if issue.description %}
  {{ issue.description }}
  {% else %}
  No description provided.
  {% endif %}
  """

  @type codex_runtime_settings :: %{
          approval_policy: String.t() | map(),
          thread_sandbox: String.t(),
          turn_sandbox_policy: map()
        }

  @spec settings() :: {:ok, Schema.t()} | {:error, term()}
  def settings do
    case Workflow.current() do
      {:ok, %{config: config}} when is_map(config) ->
        Schema.parse(config)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec settings!() :: Schema.t()
  def settings! do
    case settings() do
      {:ok, settings} ->
        settings

      {:error, reason} ->
        raise ArgumentError, message: format_config_error(reason)
    end
  end

  @spec max_concurrent_agents_for_state(term()) :: pos_integer()
  def max_concurrent_agents_for_state(state_name) when is_binary(state_name) do
    config = settings!()

    Map.get(
      config.agent.max_concurrent_agents_by_state,
      Schema.normalize_issue_state(state_name),
      config.agent.max_concurrent_agents
    )
  end

  def max_concurrent_agents_for_state(_state_name), do: settings!().agent.max_concurrent_agents

  @spec codex_turn_sandbox_policy(Path.t() | nil) :: map()
  def codex_turn_sandbox_policy(workspace \\ nil) do
    case Schema.resolve_runtime_turn_sandbox_policy(settings!(), workspace) do
      {:ok, policy} ->
        policy

      {:error, reason} ->
        raise ArgumentError, message: "Invalid codex turn sandbox policy: #{inspect(reason)}"
    end
  end

  @spec workflow_prompt() :: String.t()
  def workflow_prompt do
    case Workflow.current() do
      {:ok, %{prompt_template: prompt}} ->
        if String.trim(prompt) == "", do: @default_prompt_template, else: prompt

      _ ->
        @default_prompt_template
    end
  end

  @spec server_port() :: non_neg_integer() | nil
  def server_port do
    case Application.get_env(:odyssey_elixir, :server_port_override) do
      port when is_integer(port) and port >= 0 -> port
      _ -> settings!().server.port
    end
  end

  @spec agent_role_for_state(String.t()) :: :coder | :review
  def agent_role_for_state(state_name) when is_binary(state_name) do
    s = settings!()

    if s.review_agent.enabled do
      review_state = Schema.normalize_issue_state(s.review_agent.state_name || "ai review")
      if Schema.normalize_issue_state(state_name) == review_state, do: :review, else: :coder
    else
      :coder
    end
  end

  def agent_role_for_state(_state_name), do: :coder

  @spec agent_codex_config(:coder | :review) :: map()
  def agent_codex_config(:review), do: settings!().review_agent
  def agent_codex_config(_role), do: settings!().codex

  @spec agent_backend(:coder | :review) :: module()
  def agent_backend(role) do
    case agent_codex_config(role).provider do
      "claude_code" -> OdysseyElixir.ClaudeCode.CliClient
      _ -> OdysseyElixir.Codex.AppServer
    end
  end

  @default_review_prompt """
  You are a code review agent for Linear ticket `{{ issue.identifier }}`.

  Issue: {{ issue.identifier }} — {{ issue.title }}
  URL: {{ issue.url }}

  Review the pull request for this issue. Check out the PR branch, review the diff against origin/main, and post your findings as a PR comment.

  Focus on: correctness, bugs, test coverage, security issues. Ignore style nitpicks.

  Decision:
  - APPROVE: `gh pr comment -b "LGTM: <summary>"` then move issue to Merging. Do NOT use `gh pr review --approve`.
  - REQUEST_CHANGES: `gh pr comment -b "Changes needed: <feedback>"` then move issue to In Progress.
  """

  @spec review_agent_prompt() :: String.t()
  def review_agent_prompt do
    case settings!().review_agent.prompt do
      prompt when is_binary(prompt) and prompt != "" -> prompt
      _ -> @default_review_prompt
    end
  end

  @spec approval_gate_enabled?(atom()) :: boolean()
  def approval_gate_enabled?(gate) when gate in [:before_dispatch, :before_merge] do
    settings = settings!()

    case Map.get(settings, :approval_gates) do
      %{^gate => true} -> true
      _ -> false
    end
  end

  @spec validate!() :: :ok | {:error, term()}
  def validate! do
    with {:ok, settings} <- settings() do
      validate_semantics(settings)
    end
  end

  @spec codex_runtime_settings(Path.t() | nil, keyword()) ::
          {:ok, codex_runtime_settings()} | {:error, term()}
  def codex_runtime_settings(workspace \\ nil, opts \\ []) do
    with {:ok, settings} <- settings() do
      with {:ok, turn_sandbox_policy} <-
             Schema.resolve_runtime_turn_sandbox_policy(settings, workspace, opts) do
        {:ok,
         %{
           approval_policy: settings.codex.approval_policy,
           thread_sandbox: settings.codex.thread_sandbox,
           turn_sandbox_policy: turn_sandbox_policy
         }}
      end
    end
  end

  defp validate_semantics(settings) do
    cond do
      is_nil(settings.tracker.kind) ->
        {:error, :missing_tracker_kind}

      settings.tracker.kind not in ["linear", "jira", "github", "memory"] ->
        {:error, {:unsupported_tracker_kind, settings.tracker.kind}}

      settings.tracker.kind == "linear" and not is_binary(settings.tracker.api_key) ->
        {:error, :missing_linear_api_token}

      settings.tracker.kind == "linear" and not is_binary(settings.tracker.project_slug) ->
        {:error, :missing_linear_project_slug}

      settings.tracker.kind == "jira" and not is_binary(settings.tracker.api_key) ->
        {:error, :missing_jira_api_token}

      settings.tracker.kind == "jira" and not is_binary(settings.tracker.base_url) ->
        {:error, :missing_jira_base_url}

      settings.tracker.kind == "jira" and not is_binary(settings.tracker.project_key) ->
        {:error, :missing_jira_project_key}

      settings.tracker.kind == "github" and not is_binary(settings.tracker.api_key) ->
        {:error, :missing_github_token}

      settings.tracker.kind == "github" and not is_binary(settings.tracker.repo) ->
        {:error, :missing_github_repo}

      true ->
        :ok
    end
  end

  defp format_config_error(reason) do
    case reason do
      {:invalid_workflow_config, message} ->
        "Invalid WORKFLOW.md config: #{message}"

      {:missing_workflow_file, path, raw_reason} ->
        "Missing WORKFLOW.md at #{path}: #{inspect(raw_reason)}"

      {:workflow_parse_error, raw_reason} ->
        "Failed to parse WORKFLOW.md: #{inspect(raw_reason)}"

      :workflow_front_matter_not_a_map ->
        "Failed to parse WORKFLOW.md: workflow front matter must decode to a map"

      other ->
        "Invalid WORKFLOW.md config: #{inspect(other)}"
    end
  end
end
