defmodule TcgCheapWeb.Admin.ImportIssueLive do
  @moduledoc "Authenticated, read-only AshBackpex inspection of normalized import issues."

  use AshBackpex.LiveResource

  backpex do
    resource TcgCheap.Operations.ImportIssue
    layout({TcgCheapWeb.Layouts, :admin})
    read_action(:admin_catalogue)
    singular_name("Import issue")
    plural_name("Import issues")
    init_order(%{by: :id, direction: :desc})
    per_page_default(15)
    per_page_options([15, 50])

    panels(issue: "Issue", target: "Target", timing: "Timing")

    fields do
      field :provider_key, searchable: true, orderable: false, panel: :target
      field :operation, orderable: false, panel: :issue
      field :stage, orderable: false, panel: :issue
      field :target_type, orderable: false, panel: :target
      field :target_key, searchable: true, orderable: false, panel: :target
      field :issue_kind, orderable: false, panel: :issue
      field :issue_code, orderable: false, panel: :issue
      field :first_seen_at, orderable: false, panel: :timing
      field :last_seen_at, orderable: false, panel: :timing
      field :inserted_at, only: [:show], orderable: false, panel: :timing
      field :updated_at, only: [:show], orderable: false, panel: :timing
    end

    item_actions do
      strip_default([:edit, :delete])
    end
  end
end
