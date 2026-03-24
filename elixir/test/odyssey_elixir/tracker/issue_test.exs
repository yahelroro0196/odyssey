defmodule OdysseyElixir.Tracker.IssueTest do
  use ExUnit.Case, async: true

  alias OdysseyElixir.Tracker.Issue

  describe "struct defaults" do
    test "has expected default values" do
      issue = %Issue{}
      assert issue.labels == []
      assert issue.blocked_by == []
      assert issue.assigned_to_worker == true
      assert issue.id == nil
      assert issue.title == nil
      assert issue.state == nil
      assert issue.created_at == nil
      assert issue.updated_at == nil
    end
  end

  describe "label_names/1" do
    test "returns labels list" do
      issue = %Issue{labels: ["bug", "urgent"]}
      assert Issue.label_names(issue) == ["bug", "urgent"]
    end

    test "returns empty list when no labels" do
      issue = %Issue{labels: []}
      assert Issue.label_names(issue) == []
    end
  end
end
