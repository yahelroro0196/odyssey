defmodule OdysseyElixir.PromptBuilderTest do
  use OdysseyElixir.TestSupport

  describe "build_prompt/2" do
    test "renders issue fields into template" do
      write_workflow_file!(Workflow.workflow_file_path(),
        prompt:
          "ID: {{ issue.identifier }}\nTitle: {{ issue.title }}\nState: {{ issue.state }}\nURL: {{ issue.url }}\nLabels: {{ issue.labels | join: \", \" }}"
      )

      issue = %Issue{
        identifier: "TEST-1",
        title: "Fix the bug",
        description: "Some details",
        state: "In Progress",
        url: "https://example.com/TEST-1",
        labels: ["bug", "urgent"]
      }

      result = PromptBuilder.build_prompt(issue)
      assert result =~ "ID: TEST-1"
      assert result =~ "Title: Fix the bug"
      assert result =~ "State: In Progress"
      assert result =~ "URL: https://example.com/TEST-1"
      assert result =~ "Labels: bug, urgent"
    end

    test "handles nil description with conditional" do
      write_workflow_file!(Workflow.workflow_file_path(),
        prompt:
          "{% if issue.description %}{{ issue.description }}{% else %}No description{% endif %}"
      )

      issue = %Issue{identifier: "TEST-2", title: "No desc", description: nil}
      result = PromptBuilder.build_prompt(issue)
      assert result =~ "No description"
    end

    test "renders attempt number from context" do
      write_workflow_file!(Workflow.workflow_file_path(),
        prompt: "Attempt: {{ attempt }}"
      )

      issue = %Issue{identifier: "TEST-3", title: "Retry"}
      result = PromptBuilder.build_prompt(issue, attempt: 3)
      assert result =~ "Attempt: 3"
    end

    test "uses default prompt when workflow prompt is empty" do
      write_workflow_file!(Workflow.workflow_file_path(), prompt: "")

      issue = %Issue{
        identifier: "TEST-4",
        title: "Default prompt test",
        description: "body text"
      }

      result = PromptBuilder.build_prompt(issue)
      assert result =~ "TEST-4"
      assert result =~ "Default prompt test"
    end

    test "raises on unparseable template" do
      write_workflow_file!(Workflow.workflow_file_path(),
        prompt: "{% invalid_tag %}"
      )

      issue = %Issue{identifier: "TEST-5", title: "Bad template"}

      assert_raise RuntimeError, ~r/template_parse_error/, fn ->
        PromptBuilder.build_prompt(issue)
      end
    end
  end

  describe "build_review_prompt/2" do
    test "renders review template with issue fields" do
      issue = %Issue{
        identifier: "TEST-6",
        title: "Review this",
        url: "https://example.com/TEST-6"
      }

      result = PromptBuilder.build_review_prompt(issue)
      assert result =~ "TEST-6"
      assert result =~ "Review this"
    end

    test "renders attempt in review prompt" do
      issue = %Issue{
        identifier: "TEST-7",
        title: "Review retry",
        url: "https://example.com/TEST-7"
      }

      result = PromptBuilder.build_review_prompt(issue, attempt: 2)
      assert result =~ "TEST-7"
    end
  end
end
