defmodule OdysseyElixir.Codex.DynamicTool do
  @moduledoc """
  Executes client-side tool calls requested by Codex app-server turns.
  """

  alias OdysseyElixir.{Config, Linear.Client}

  @linear_graphql_tool "linear_graphql"
  @linear_graphql_description """
  Execute a raw GraphQL query or mutation against Linear using Odyssey's configured auth.
  """
  @linear_graphql_input_schema %{
    "type" => "object",
    "additionalProperties" => false,
    "required" => ["query"],
    "properties" => %{
      "query" => %{
        "type" => "string",
        "description" => "GraphQL query or mutation document to execute against Linear."
      },
      "variables" => %{
        "type" => ["object", "null"],
        "description" => "Optional GraphQL variables object.",
        "additionalProperties" => true
      }
    }
  }

  @jira_api_tool "jira_api"
  @jira_api_description """
  Execute a REST API call against Jira using Odyssey's configured auth.
  """
  @jira_api_input_schema %{
    "type" => "object",
    "additionalProperties" => false,
    "required" => ["method", "path"],
    "properties" => %{
      "method" => %{
        "type" => "string",
        "description" => "HTTP method (GET, POST, PUT, DELETE, PATCH)."
      },
      "path" => %{
        "type" => "string",
        "description" => "REST API path (e.g. /rest/api/3/issue/PROJ-1)."
      },
      "body" => %{
        "type" => ["object", "null"],
        "description" => "Optional JSON request body.",
        "additionalProperties" => true
      }
    }
  }

  @github_api_tool "github_api"
  @github_api_description """
  Execute a REST API call against GitHub using Odyssey's configured auth.
  """
  @github_api_input_schema %{
    "type" => "object",
    "additionalProperties" => false,
    "required" => ["method", "path"],
    "properties" => %{
      "method" => %{
        "type" => "string",
        "description" => "HTTP method (GET, POST, PUT, DELETE, PATCH)."
      },
      "path" => %{
        "type" => "string",
        "description" => "GitHub API path (e.g. /repos/owner/repo/issues/1)."
      },
      "body" => %{
        "type" => ["object", "null"],
        "description" => "Optional JSON request body.",
        "additionalProperties" => true
      }
    }
  }

  @spec execute(String.t() | nil, term(), keyword()) :: map()
  def execute(tool, arguments, opts \\ []) do
    case tool do
      @linear_graphql_tool ->
        execute_linear_graphql(arguments, opts)

      @jira_api_tool ->
        execute_jira_api(arguments)

      @github_api_tool ->
        execute_github_api(arguments)

      other ->
        failure_response(%{
          "error" => %{
            "message" => "Unsupported dynamic tool: #{inspect(other)}.",
            "supportedTools" => supported_tool_names()
          }
        })
    end
  end

  @spec tool_specs() :: [map()]
  def tool_specs do
    case Config.settings!().tracker.kind do
      "jira" ->
        [
          %{
            "name" => @jira_api_tool,
            "description" => @jira_api_description,
            "inputSchema" => @jira_api_input_schema
          }
        ]

      "github" ->
        [
          %{
            "name" => @github_api_tool,
            "description" => @github_api_description,
            "inputSchema" => @github_api_input_schema
          }
        ]

      _ ->
        [
          %{
            "name" => @linear_graphql_tool,
            "description" => @linear_graphql_description,
            "inputSchema" => @linear_graphql_input_schema
          }
        ]
    end
  end

  defp execute_jira_api(arguments) when is_map(arguments) do
    with {:ok, method} <- extract_string(arguments, "method"),
         {:ok, path} <- extract_string(arguments, "path") do
      body = Map.get(arguments, "body") || Map.get(arguments, :body)

      case OdysseyElixir.Jira.Client.rest_api(method, path, body) do
        {:ok, response} -> rest_api_response(response)
        {:error, reason} -> failure_response(tool_error_payload(reason))
      end
    else
      {:error, reason} -> failure_response(tool_error_payload(reason))
    end
  end

  defp execute_jira_api(_arguments), do: failure_response(tool_error_payload(:invalid_arguments))

  defp execute_github_api(arguments) when is_map(arguments) do
    with {:ok, method} <- extract_string(arguments, "method"),
         {:ok, path} <- extract_string(arguments, "path") do
      body = Map.get(arguments, "body") || Map.get(arguments, :body)

      case OdysseyElixir.GitHub.Client.rest_api(method, path, body) do
        {:ok, response} -> rest_api_response(response)
        {:error, reason} -> failure_response(tool_error_payload(reason))
      end
    else
      {:error, reason} -> failure_response(tool_error_payload(reason))
    end
  end

  defp execute_github_api(_arguments), do: failure_response(tool_error_payload(:invalid_arguments))

  defp extract_string(map, key) do
    value = Map.get(map, key) || Map.get(map, String.to_existing_atom(key))

    case value do
      v when is_binary(v) and v != "" -> {:ok, v}
      _ -> {:error, {:missing_field, key}}
    end
  rescue
    ArgumentError -> {:error, {:missing_field, key}}
  end

  defp rest_api_response(response) do
    dynamic_tool_response(true, encode_payload(response))
  end

  defp execute_linear_graphql(arguments, opts) do
    linear_client = Keyword.get(opts, :linear_client, &Client.graphql/3)

    with {:ok, query, variables} <- normalize_linear_graphql_arguments(arguments),
         {:ok, response} <- linear_client.(query, variables, []) do
      graphql_response(response)
    else
      {:error, reason} ->
        failure_response(tool_error_payload(reason))
    end
  end

  defp normalize_linear_graphql_arguments(arguments) when is_binary(arguments) do
    case String.trim(arguments) do
      "" -> {:error, :missing_query}
      query -> {:ok, query, %{}}
    end
  end

  defp normalize_linear_graphql_arguments(arguments) when is_map(arguments) do
    case normalize_query(arguments) do
      {:ok, query} ->
        case normalize_variables(arguments) do
          {:ok, variables} ->
            {:ok, query, variables}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_linear_graphql_arguments(_arguments), do: {:error, :invalid_arguments}

  defp normalize_query(arguments) do
    case Map.get(arguments, "query") || Map.get(arguments, :query) do
      query when is_binary(query) ->
        case String.trim(query) do
          "" -> {:error, :missing_query}
          trimmed -> {:ok, trimmed}
        end

      _ ->
        {:error, :missing_query}
    end
  end

  defp normalize_variables(arguments) do
    case Map.get(arguments, "variables") || Map.get(arguments, :variables) || %{} do
      variables when is_map(variables) -> {:ok, variables}
      _ -> {:error, :invalid_variables}
    end
  end

  defp graphql_response(response) do
    success =
      case response do
        %{"errors" => errors} when is_list(errors) and errors != [] -> false
        %{errors: errors} when is_list(errors) and errors != [] -> false
        _ -> true
      end

    dynamic_tool_response(success, encode_payload(response))
  end

  defp failure_response(payload) do
    dynamic_tool_response(false, encode_payload(payload))
  end

  defp dynamic_tool_response(success, output) when is_boolean(success) and is_binary(output) do
    %{
      "success" => success,
      "output" => output,
      "contentItems" => [
        %{
          "type" => "inputText",
          "text" => output
        }
      ]
    }
  end

  defp encode_payload(payload) when is_map(payload) or is_list(payload) do
    Jason.encode!(payload, pretty: true)
  end

  defp encode_payload(payload), do: inspect(payload)

  defp tool_error_payload(:missing_query) do
    %{
      "error" => %{
        "message" => "`linear_graphql` requires a non-empty `query` string."
      }
    }
  end

  defp tool_error_payload(:invalid_arguments) do
    %{
      "error" => %{
        "message" => "`linear_graphql` expects either a GraphQL query string or an object with `query` and optional `variables`."
      }
    }
  end

  defp tool_error_payload(:invalid_variables) do
    %{
      "error" => %{
        "message" => "`linear_graphql.variables` must be a JSON object when provided."
      }
    }
  end

  defp tool_error_payload(:missing_linear_api_token) do
    %{
      "error" => %{
        "message" => "Odyssey is missing Linear auth. Set `linear.api_key` in `WORKFLOW.md` or export `LINEAR_API_KEY`."
      }
    }
  end

  defp tool_error_payload({:linear_api_status, status}) do
    %{
      "error" => %{
        "message" => "Linear GraphQL request failed with HTTP #{status}.",
        "status" => status
      }
    }
  end

  defp tool_error_payload({:linear_api_request, reason}) do
    %{
      "error" => %{
        "message" => "Linear GraphQL request failed before receiving a successful response.",
        "reason" => inspect(reason)
      }
    }
  end

  defp tool_error_payload({:missing_field, field}) do
    %{
      "error" => %{
        "message" => "Required field `#{field}` is missing or empty."
      }
    }
  end

  defp tool_error_payload({:jira_api_status, status}) do
    %{
      "error" => %{
        "message" => "Jira API request failed with HTTP #{status}.",
        "status" => status
      }
    }
  end

  defp tool_error_payload({:jira_api_request, reason}) do
    %{
      "error" => %{
        "message" => "Jira API request failed.",
        "reason" => inspect(reason)
      }
    }
  end

  defp tool_error_payload({:github_api_status, status}) do
    %{
      "error" => %{
        "message" => "GitHub API request failed with HTTP #{status}.",
        "status" => status
      }
    }
  end

  defp tool_error_payload({:github_api_request, reason}) do
    %{
      "error" => %{
        "message" => "GitHub API request failed.",
        "reason" => inspect(reason)
      }
    }
  end

  defp tool_error_payload(reason) do
    %{
      "error" => %{
        "message" => "Tool execution failed.",
        "reason" => inspect(reason)
      }
    }
  end

  defp supported_tool_names do
    Enum.map(tool_specs(), & &1["name"])
  end
end
