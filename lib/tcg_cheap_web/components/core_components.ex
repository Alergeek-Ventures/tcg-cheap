defmodule TcgCheapWeb.CoreComponents do
  alias Phoenix.HTML.Form

  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://phoenix-live-view.hexdocs.pm/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash
        id="welcome-back"
        kind={:info}
        phx-mounted={show("#welcome-back") |> JS.remove_attribute("hidden")}
        hidden
      >
        Welcome Back!
      </.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label="close">
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-primary btn-soft"}

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://phoenix-html.hexdocs.pm/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[@class || "w-full select", @errors != [] && (@error_class || "select-error")]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || "w-full input",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">Actions</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  Renders a decorative Fluent UI System Icon.

  The path data is from Microsoft's
  [Fluent UI System Icons](https://github.com/microsoft/fluentui-system-icons),
  used under the [MIT License](https://github.com/microsoft/fluentui-system-icons/blob/main/LICENSE).

  ## Examples

      <.fluent_icon name={:arrow_left} />
      <.fluent_icon name={:search} class="size-5" />
  """
  attr :name, :atom,
    required: true,
    values: [
      :arrow_left,
      :info,
      :clock,
      :arrow_trending,
      :arrow_swap,
      :chevron_down,
      :search,
      :filter,
      :dismiss,
      :checkmark_circle,
      :dismiss_circle,
      :card_ui,
      :stack,
      :ribbon,
      :box,
      :data_pie,
      :location,
      :shield_error,
      :mail,
      :key,
      :arrow_clockwise,
      :eye,
      :tag,
      :image,
      :hourglass,
      :shield
    ]

  attr :class, :any, default: "size-4"

  def fluent_icon(assigns) do
    {view_box, path} = fluent_icon_path(assigns.name)
    assigns = assign(assigns, view_box: view_box, path: path)

    ~H"""
    <svg
      class={["fluent-icon", @class]}
      aria-hidden="true"
      focusable="false"
      viewBox={@view_box}
      fill="currentColor"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path d={@path} />
    </svg>
    """
  end

  defp fluent_icon_path(:arrow_left) do
    {"0 0 20 20",
     "M9.15898 16.8666C9.36292 17.0528 9.67918 17.0384 9.86536 16.8345C10.0515 16.6305 10.0371 16.3143 9.8332 16.1281L3.66535 10.4974H17.4961C17.7722 10.4974 17.9961 10.2735 17.9961 9.99736C17.9961 9.72122 17.7722 9.49736 17.4961 9.49736H3.66824L9.8332 3.86927C10.0371 3.68309 10.0515 3.36684 9.86536 3.16289C9.67918 2.95895 9.36292 2.94456 9.15898 3.13074L2.24263 9.44478C2.10268 9.57254 2.02285 9.74008 2.00314 9.91323C1.99851 9.94058 1.99609 9.96869 1.99609 9.99736C1.99609 10.0242 1.99821 10.0506 2.00229 10.0763C2.02047 10.2522 2.10058 10.4229 2.24263 10.5526L9.15898 16.8666Z"}
  end

  defp fluent_icon_path(:info) do
    {"0 0 20 20",
     "M10.4921 8.91012C10.4497 8.67687 10.2456 8.49999 10.0001 8.49999C9.72397 8.49999 9.50011 8.72385 9.50011 8.99999V13.5021L9.50817 13.592C9.55051 13.8253 9.75465 14.0021 10.0001 14.0021C10.2763 14.0021 10.5001 13.7783 10.5001 13.5021V8.99999L10.4921 8.91012ZM10.7988 6.74999C10.7988 6.33578 10.463 5.99999 10.0488 5.99999C9.63461 5.99999 9.29883 6.33578 9.29883 6.74999C9.29883 7.16421 9.63461 7.49999 10.0488 7.49999C10.463 7.49999 10.7988 7.16421 10.7988 6.74999ZM18 10C18 5.58172 14.4183 2 10 2C5.58172 2 2 5.58172 2 10C2 14.4183 5.58172 18 10 18C14.4183 18 18 14.4183 18 10ZM3 10C3 6.13401 6.13401 3 10 3C13.866 3 17 6.13401 17 10C17 13.866 13.866 17 10 17C6.13401 17 3 13.866 3 10Z"}
  end

  defp fluent_icon_path(:clock) do
    {"0 0 16 16",
     "M2 8C2 4.68629 4.68629 2 8 2C11.3137 2 14 4.68629 14 8C14 11.3137 11.3137 14 8 14C4.68629 14 2 11.3137 2 8ZM8 1C4.13401 1 1 4.13401 1 8C1 11.866 4.13401 15 8 15C11.866 15 15 11.866 15 8C15 4.13401 11.866 1 8 1ZM8 4.5C8 4.22386 7.77614 4 7.5 4C7.22386 4 7 4.22386 7 4.5V8.5C7 8.77614 7.22386 9 7.5 9H10.5C10.7761 9 11 8.77614 11 8.5C11 8.22386 10.7761 8 10.5 8H8V4.5Z"}
  end

  defp fluent_icon_path(:arrow_trending) do
    {"0 0 20 20",
     "M17.9621 5.30861C17.9377 5.24964 17.9015 5.19439 17.8536 5.14645C17.8056 5.09851 17.7504 5.06234 17.6914 5.03794C17.6324 5.01349 17.5678 5 17.5 5H11.5C11.2239 5 11 5.22386 11 5.5C11 5.77614 11.2239 6 11.5 6H16.2929L10.5 11.7929L8.35355 9.64645C8.15829 9.45118 7.84171 9.45118 7.64645 9.64645L2.14645 15.1464C1.95118 15.3417 1.95118 15.6583 2.14645 15.8536C2.34171 16.0488 2.65829 16.0488 2.85355 15.8536L8 10.7071L10.1464 12.8536C10.3417 13.0488 10.6583 13.0488 10.8536 12.8536L17 6.70711V11.5C17 11.7761 17.2239 12 17.5 12C17.7761 12 18 11.7761 18 11.5V5.5C18 5.43221 17.9865 5.36756 17.9621 5.30861Z"}
  end

  defp fluent_icon_path(:arrow_swap) do
    {"0 0 20 20",
     "M12.1464 3.14645C12.3417 2.95118 12.6583 2.95118 12.8536 3.14645L15.8536 6.14645C16.0488 6.34171 16.0488 6.65829 15.8536 6.85355L12.8536 9.85355C12.6583 10.0488 12.3417 10.0488 12.1464 9.85355C11.9512 9.65829 11.9512 9.34171 12.1464 9.14645L14.2929 7H4.5C4.22386 7 4 6.77614 4 6.5C4 6.22386 4.22386 6 4.5 6H14.2929L12.1464 3.85355C11.9512 3.65829 11.9512 3.34171 12.1464 3.14645ZM7.85355 10.1464C8.04882 10.3417 8.04882 10.6583 7.85355 10.8536L5.70711 13H15.5C15.7761 13 16 13.2239 16 13.5C16 13.7761 15.7761 14 15.5 14H5.70711L7.85355 16.1464C8.04882 16.3417 8.04882 16.6583 7.85355 16.8536C7.65829 17.0488 7.34171 17.0488 7.14645 16.8536L4.14645 13.8536C3.95118 13.6583 3.95118 13.3417 4.14645 13.1464L7.14645 10.1464C7.34171 9.95118 7.65829 9.95118 7.85355 10.1464Z"}
  end

  defp fluent_icon_path(:location) do
    {"0 0 20 20",
     "M5.05043 4.05139C7.7841 1.31653 12.2162 1.31653 14.9498 4.05139C17.6833 6.78621 17.6833 11.2199 14.9498 13.9547L13.8219 15.069L11.3864 17.4391C10.6565 18.1455 9.52149 18.1843 8.74672 17.5563L8.61391 17.4391L6.57094 15.4537L5.05043 13.9547C2.31681 11.2199 2.3168 6.78625 5.05043 4.05139ZM14.2448 4.75647C11.9003 2.41099 8.09899 2.41099 5.75454 4.75647C3.47055 7.04183 3.41265 10.7109 5.57973 13.067L5.75454 13.2496L6.32582 13.817L9.30727 16.7223L9.40004 16.8024C9.7542 17.0701 10.2461 17.07 10.6002 16.8024L10.693 16.7223L12.9235 14.5543L14.2448 13.2496L14.4206 13.067C16.5877 10.7107 16.5291 7.04181 14.2448 4.75647ZM9.99965 6.24963C11.5183 6.24963 12.7495 7.48102 12.7497 8.99963C12.7497 10.5184 11.5184 11.7496 9.99965 11.7496C8.48103 11.7494 7.24965 10.5183 7.24965 8.99963C7.24985 7.48113 8.48115 6.24982 9.99965 6.24963ZM9.99965 7.24963C9.03343 7.24982 8.24985 8.03342 8.24965 8.99963C8.24965 9.96602 9.03331 10.7494 9.99965 10.7496C10.9662 10.7496 11.7497 9.96613 11.7497 8.99963C11.7495 8.0333 10.966 7.24963 9.99965 7.24963Z"}
  end

  defp fluent_icon_path(:shield_error) do
    {"0 0 20 20",
     "M10 6C10.2761 6 10.5 6.22386 10.5 6.5V11.5C10.5 11.7761 10.2761 12 10 12C9.72386 12 9.5 11.7761 9.5 11.5V6.5C9.5 6.22386 9.72386 6 10 6ZM10 14.5C10.4142 14.5 10.75 14.1642 10.75 13.75C10.75 13.3358 10.4142 13 10 13C9.58579 13 9.25 13.3358 9.25 13.75C9.25 14.1642 9.58579 14.5 10 14.5ZM9.72265 2.08397C9.8906 1.97201 10.1094 1.97201 10.2774 2.08397C12.2155 3.3761 14.3117 4.1823 16.5707 4.50503C16.817 4.54021 17 4.75117 17 5V9.5C17 13.3913 14.693 16.2307 10.1795 17.9667C10.064 18.0111 9.93604 18.0111 9.82051 17.9667C5.30699 16.2307 3 13.3913 3 9.5V5C3 4.75117 3.18297 4.54021 3.42929 4.50503C5.68833 4.1823 7.78446 3.3761 9.72265 2.08397ZM9.59914 3.34583C7.85275 4.39606 5.98541 5.09055 4 5.42787V9.5C4 12.892 5.96795 15.3634 10 16.9632C14.0321 15.3634 16 12.892 16 9.5V5.42787C14.0146 5.09055 12.1473 4.39606 10.4009 3.34583L10 3.09715L9.59914 3.34583Z"}
  end

  defp fluent_icon_path(:chevron_down) do
    {"0 0 16 16",
     "M3.14645 5.64645C3.34171 5.45118 3.65829 5.45118 3.85355 5.64645L8 9.79289L12.1464 5.64645C12.3417 5.45118 12.6583 5.45118 12.8536 5.64645C13.0488 5.84171 13.0488 6.15829 12.8536 6.35355L8.35355 10.8536C8.15829 11.0488 7.84171 11.0488 7.64645 10.8536L3.14645 6.35355C2.95118 6.15829 2.95118 5.84171 3.14645 5.64645Z"}
  end

  defp fluent_icon_path(:search) do
    {"0 0 20 20",
     "M13.7291 14.4362C12.5924 15.411 11.115 16 9.5 16C5.91015 16 3 13.0899 3 9.5C3 5.91015 5.91015 3 9.5 3C13.0899 3 16 5.91015 16 9.5C16 11.115 15.411 12.5924 14.4361 13.7292L17.8535 17.1465C18.0487 17.3417 18.0487 17.6583 17.8535 17.8536C17.6799 18.0271 17.4105 18.0464 17.2156 17.9114L17.1464 17.8536L13.7291 14.4362ZM13.0196 13.7266C13.276 13.5128 13.5127 13.2761 13.7265 13.0197C14.5216 12.0659 15 10.8388 15 9.5C15 6.46243 12.5376 4 9.5 4C6.46243 4 4 6.46243 4 9.5C4 12.5376 6.46243 15 9.5 15C10.8388 15 12.0658 14.5217 13.0196 13.7266Z"}
  end

  defp fluent_icon_path(:filter) do
    {"0 0 20 20",
     "M3 5.5A.5.5 0 0 1 3.5 5h13a.5.5 0 0 1 0 1h-13a.5.5 0 0 1-.5-.5Zm2 4a.5.5 0 0 1 .5-.5h9a.5.5 0 0 1 0 1h-9a.5.5 0 0 1-.5-.5Zm2 4a.5.5 0 0 1 .5-.5h5a.5.5 0 0 1 0 1h-5a.5.5 0 0 1-.5-.5Z"}
  end

  defp fluent_icon_path(:checkmark_circle) do
    {"0 0 20 20",
     "M10 2a8 8 0 1 1 0 16 8 8 0 0 1 0-16Zm3.36 5.65a.5.5 0 0 0-.64-.06l-.07.06L9 11.3 7.35 9.65l-.07-.06a.5.5 0 0 0-.7.7l.07.07 2 2 .07.06c.17.11.4.11.56 0l.07-.06 4-4 .07-.08a.5.5 0 0 0-.06-.63Z"}
  end

  defp fluent_icon_path(:dismiss_circle) do
    {"0 0 20 20",
     "M10 2a8 8 0 1 1 0 16 8 8 0 0 1 0-16ZM7.8 7.11a.5.5 0 0 0-.63.06l-.06.07a.5.5 0 0 0 .06.64L9.3 10l-2.12 2.12-.06.07a.5.5 0 0 0 .06.64l.07.06c.2.13.47.11.64-.06L10 10.7l2.12 2.12.07.06c.2.13.46.11.64-.06l.06-.07a.5.5 0 0 0-.06-.64L10.7 10l2.12-2.12.06-.07a.5.5 0 0 0-.06-.64l-.07-.06a.5.5 0 0 0-.64.06L10 9.3 7.88 7.17l-.07-.06Z"}
  end

  defp fluent_icon_path(:dismiss) do
    {"0 0 20 20",
     "M4.08859 4.21569L4.14645 4.14645C4.32001 3.97288 4.58944 3.9536 4.78431 4.08859L4.85355 4.14645L10 9.293L15.1464 4.14645C15.32 3.97288 15.5894 3.9536 15.7843 4.08859L15.8536 4.14645C16.0271 4.32001 16.0464 4.58944 15.9114 4.78431L15.8536 4.85355L10.707 10L15.8536 15.1464C16.0271 15.32 16.0464 15.5894 15.9114 15.7843L15.8536 15.8536C15.68 16.0271 15.4106 16.0464 15.2157 15.9114L15.1464 15.8536L10 10.707L4.85355 15.8536C4.67999 16.0271 4.41056 16.0464 4.21569 15.9114L4.14645 15.8536C3.97288 15.68 3.9536 15.4106 4.08859 15.2157L4.14645 15.1464L9.293 10L4.14645 4.85355C3.97288 4.67999 3.9536 4.41056 4.08859 4.21569L4.14645 4.14645L4.08859 4.21569Z"}
  end

  defp fluent_icon_path(:card_ui) do
    {"0 0 20 20",
     "M4.5 4C3.11929 4 2 5.11929 2 6.5V13.5C2 14.8807 3.11929 16 4.5 16H15.5C16.8807 16 18 14.8807 18 13.5V6.5C18 5.11929 16.8807 4 15.5 4H4.5ZM3 6.5C3 5.67157 3.67157 5 4.5 5H15.5C16.3284 5 17 5.67157 17 6.5V13.5C17 14.3284 16.3284 15 15.5 15H4.5C3.67157 15 3 14.3284 3 13.5V6.5ZM4.5 6C4.22386 6 4 6.22386 4 6.5C4 6.77614 4.22386 7 4.5 7H9.5C9.77614 7 10 6.77614 10 6.5C10 6.22386 9.77614 6 9.5 6H4.5ZM4.5 8C4.22386 8 4 8.22386 4 8.5C4 8.77614 4.22386 9 4.5 9H12.5C12.7761 9 13 8.77614 13 8.5C13 8.22386 12.7761 8 12.5 8H4.5ZM5 11C4.44772 11 4 11.4477 4 12V13C4 13.5523 4.44772 14 5 14H9C9.55228 14 10 13.5523 10 13V12C10 11.4477 9.55228 11 9 11H5Z"}
  end

  defp fluent_icon_path(:stack) do
    {"0 0 20 20",
     "M2 5C2 3.89543 2.89543 3 4 3H12C13.1046 3 14 3.89543 14 5V11C14 12.1046 13.1046 13 12 13H4C2.89543 13 2 12.1046 2 11V5ZM4 4C3.44772 4 3 4.44772 3 5V11C3 11.5523 3.44772 12 4 12H12C12.5523 12 13 11.5523 13 11V5C13 4.44772 12.5523 4 12 4H4ZM6.00001 15C5.25973 15 4.61339 14.5978 4.26758 14H12C13.6569 14 15 12.6569 15 11V5.26758C15.5978 5.61339 16 6.25973 16 7.00001V11C16 13.2092 14.2092 15 12 15H6.00001ZM8.00001 17C7.25973 17 6.61339 16.5978 6.26758 16H12C14.7614 16 17 13.7614 17 11V7.26758C17.5978 7.61339 18 8.25973 18 9.00001V11C18 14.3137 15.3137 17 12 17H8.00001Z"}
  end

  defp fluent_icon_path(:ribbon) do
    {"0 0 20 20",
     "M16 8C16 9.777 15.2275 11.3736 14 12.4722V17.5002C14 17.6784 13.9051 17.8432 13.751 17.9327C13.5968 18.0221 13.4067 18.0227 13.2519 17.9343L10 16.0761L6.74807 17.9343C6.59332 18.0227 6.40319 18.0221 6.24904 17.9327C6.09488 17.8432 6 17.6784 6 17.5002V12.4722C4.7725 11.3736 4 9.777 4 8C4 4.68629 6.68629 2 10 2C13.3137 2 16 4.68629 16 8ZM10 14C8.90714 14 7.88252 13.7078 7 13.1973V16.6386L9.75193 15.0661C9.90565 14.9782 10.0944 14.9782 10.2481 15.0661L13 16.6386V13.1973C12.1175 13.7078 11.0929 14 10 14ZM10 13C12.7614 13 15 10.7614 15 8C15 5.23858 12.7614 3 10 3C7.23858 3 5 5.23858 5 8C5 10.7614 7.23858 13 10 13Z"}
  end

  defp fluent_icon_path(:box) do
    {"0 0 20 20",
     "M11.2999 2.4808C10.4654 2.14702 9.53457 2.14702 8.70013 2.4808L2.94291 4.78369C2.37343 5.01148 2 5.56305 2 6.1764V13.8223C2 14.4357 2.37343 14.9873 2.94291 15.2151L8.70013 17.5179C9.53457 17.8517 10.4654 17.8517 11.2999 17.5179L17.0571 15.2151C17.6266 14.9873 18 14.4357 18 13.8223V6.1764C18 5.56305 17.6266 5.01148 17.0571 4.78369L11.2999 2.4808ZM9.07152 3.40928C9.66755 3.17087 10.3324 3.17087 10.9285 3.40928L16.1538 5.49941L13.8751 6.41088L7.72133 3.94935L9.07152 3.40928ZM6.37504 4.48787L12.5289 6.94939L10.0001 7.96088L3.84633 5.49935L6.37504 4.48787ZM10.5001 8.83791L17 6.23797V13.8223C17 14.0268 16.8755 14.2106 16.6857 14.2866L10.9285 16.5895C10.7889 16.6453 10.6455 16.6881 10.5001 16.7177V8.83791ZM9.50015 8.83791V16.7178C9.35467 16.6881 9.21121 16.6453 9.07152 16.5895L3.3143 14.2866C3.12448 14.2106 3 14.0268 3 13.8223V6.23785L9.50015 8.83791Z"}
  end

  defp fluent_icon_path(:data_pie) do
    {"0 0 20 20",
     "M17.9987 9.13621C17.9892 9.6337 17.5596 10 17.062 10H11C10.4477 10 10 9.55228 10 9V2.93803C10 2.44045 10.3663 2.01079 10.8638 2.0013C10.9091 2.00043 10.9545 2 11 2C14.866 2 18 5.13401 18 9C18 9.04551 17.9996 9.09091 17.9987 9.13621ZM11 3V9H17C17 5.68629 14.3137 3 11 3ZM9 4.51892C9 4.37972 8.94197 4.24683 8.83988 4.1522C8.73779 4.05758 8.60087 4.0098 8.46207 4.02036C4.84717 4.29535 2 7.31493 2 11C2 14.866 5.13401 18 9 18C12.685 18 15.7046 15.1528 15.9796 11.5379C15.9902 11.3991 15.9424 11.2622 15.8478 11.1601C15.7532 11.058 15.6203 11 15.4811 11H10.5C9.67157 11 9 10.3284 9 9.49998V4.51892ZM3 11C3 8.02704 5.16249 5.55876 8 5.08287V9.49998C8 10.8807 9.11929 12 10.5 12H14.9171C14.4412 14.8375 11.9729 17 9 17C5.68629 17 3 14.3137 3 11Z"}
  end

  defp fluent_icon_path(:mail) do
    {"0 0 20 20",
     "M15.5 4C16.8807 4 18 5.11929 18 6.5V14.5C18 15.8807 16.8807 17 15.5 17H4.5C3.11929 17 2 15.8807 2 14.5V6.5C2 5.11929 3.11929 4 4.5 4H15.5ZM17 7.961L10.2535 11.931C10.1231 12.0077 9.96661 12.0205 9.82751 11.9693L9.74649 11.931L3 7.963V14.5C3 15.3284 3.67157 16 4.5 16H15.5C16.3284 16 17 15.3284 17 14.5V7.961ZM15.5 5H4.5C3.67157 5 3 5.67157 3 6.5V6.802L10 10.9199L17 6.801V6.5C17 5.67157 16.3284 5 15.5 5Z"}
  end

  defp fluent_icon_path(:key) do
    {"0 0 20 20",
     "M15 6C15 6.55228 14.5523 7 14 7C13.4477 7 13 6.55228 13 6C13 5.44772 13.4477 5 14 5C14.5523 5 15 5.44772 15 6ZM12.5 2C9.42386 2 7 4.42386 7 7.5C7 7.89668 7.04001 8.29598 7.12154 8.67456C7.17968 8.94454 7.11378 9.17912 6.98018 9.31271L2.43934 13.8536C2.15804 14.1349 2 14.5164 2 14.9142V16.5C2 17.3284 2.67157 18 3.5 18H5.5C6.32843 18 7 17.3284 7 16.5V16H8C8.55228 16 9 15.5523 9 15V14H10C10.5523 14 11 13.5523 11 13V12.8199C11.4935 12.9536 12.0069 13 12.5 13C15.5761 13 18 10.5761 18 7.5C18 4.42386 15.5761 2 12.5 2ZM8 7.5C8 4.97614 9.97614 3 12.5 3C15.0239 3 17 4.97614 17 7.5C17 10.0239 15.0239 12 12.5 12C11.8408 12 11.2274 11.9047 10.7236 11.6528C10.5686 11.5753 10.3845 11.5836 10.2371 11.6747C10.0897 11.7658 10 11.9267 10 12.1V13H9C8.44772 13 8 13.4477 8 14V15H7C6.44772 15 6 15.4477 6 16V16.5C6 16.7761 5.77614 17 5.5 17H3.5C3.22386 17 3 16.7761 3 16.5V14.9142C3 14.7816 3.05268 14.6544 3.14645 14.5607L7.68729 10.0198C8.11942 9.58768 8.20942 8.97619 8.09913 8.46404C8.03354 8.15949 8 7.83105 8 7.5Z"}
  end

  defp fluent_icon_path(:arrow_clockwise) do
    {"0 0 20 20",
     "M4 10C4 6.68629 6.68629 4 10 4C11.7766 4 13.3732 4.77191 14.4723 6H12.5C12.2239 6 12 6.22386 12 6.5C12 6.77614 12.2239 7 12.5 7H15.5C15.7761 7 16 6.77614 16 6.5V3.5C16 3.22386 15.7761 3 15.5 3C15.2239 3 15 3.22386 15 3.5V5.10109C13.7299 3.80499 11.9591 3 10 3C6.13401 3 3 6.13401 3 10C3 13.866 6.13401 17 10 17C13.866 17 17 13.866 17 10C17 9.8191 16.9931 9.6397 16.9796 9.46207C16.9587 9.18673 16.7185 8.98049 16.4431 9.00144C16.1678 9.02239 15.9615 9.26258 15.9825 9.53793C15.9941 9.69034 16 9.84443 16 10C16 13.3137 13.3137 16 10 16C6.68629 16 4 13.3137 4 10Z"}
  end

  defp fluent_icon_path(:eye) do
    {"0 0 20 20",
     "M3.25909 11.6021C3.94254 8.32689 6.79437 6 10 6C13.2057 6 16.0574 8.32688 16.7409 11.6021C16.7974 11.8725 17.0622 12.0459 17.3325 11.9895C17.6029 11.933 17.7763 11.6682 17.7199 11.3979C16.9425 7.67312 13.6934 5 10 5C6.3066 5 3.05742 7.67311 2.28017 11.3979C2.22377 11.6682 2.39718 11.933 2.6675 11.9895C2.93782 12.0459 3.20268 11.8725 3.25909 11.6021ZM10 8C8.067 8 6.5 9.567 6.5 11.5C6.5 13.433 8.067 15 10 15C11.933 15 13.5 13.433 13.5 11.5C13.5 9.567 11.933 8 10 8ZM7.5 11.5C7.5 10.1193 8.61929 9 10 9C11.3807 9 12.5 10.1193 12.5 11.5C12.5 12.8807 11.3807 14 10 14C8.61929 14 7.5 12.8807 7.5 11.5Z"}
  end

  defp fluent_icon_path(:tag) do
    {"0 0 20 20",
     "M14 7C14.5523 7 15 6.55228 15 6C15 5.44772 14.5523 5 14 5C13.4477 5 13 5.44772 13 6C13 6.55228 13.4477 7 14 7ZM11.1292 2.00004C10.5951 1.99654 10.0818 2.20681 9.7037 2.58399L3.02216 9.24852C2.23941 10.0293 2.2386 11.297 3.02036 12.0788L7.96875 17.0271C8.7498 17.8082 10.0161 17.8082 10.7972 17.0271L17.428 10.3963C17.8038 10.0205 18.0146 9.51063 18.0138 8.97917L18.0065 4.02911C18.0049 2.93081 17.1179 2.0393 16.0196 2.0321L11.1292 2.00004ZM10.4099 3.29199C10.599 3.1034 10.8556 2.99827 11.1227 3.00002L16.013 3.03208C16.5622 3.03568 17.0057 3.48143 17.0065 4.03058L17.0138 8.98065C17.0142 9.24637 16.9088 9.50133 16.7209 9.68923L10.0901 16.32C9.69955 16.7106 9.06638 16.7106 8.67586 16.32L3.72746 11.3716C3.33659 10.9808 3.33699 10.3469 3.72836 9.95653L10.4099 3.29199Z"}
  end

  defp fluent_icon_path(:image) do
    {"0 0 20 20",
     "M14 7.5C14 8.32843 13.3284 9 12.5 9C11.6716 9 11 8.32843 11 7.5C11 6.67157 11.6716 6 12.5 6C13.3284 6 14 6.67157 14 7.5ZM13 7.5C13 7.22386 12.7761 7 12.5 7C12.2239 7 12 7.22386 12 7.5C12 7.77614 12.2239 8 12.5 8C12.7761 8 13 7.77614 13 7.5ZM3 6C3 4.34315 4.34315 3 6 3H14C15.6569 3 17 4.34315 17 6V14C17 15.6569 15.6569 17 14 17H6C4.34315 17 3 15.6569 3 14V6ZM6 4C4.89543 4 4 4.89543 4 6V14C4 14.3726 4.10191 14.7215 4.27937 15.0201L8.94868 10.432C9.53227 9.85859 10.4677 9.85859 11.0513 10.432L15.7206 15.0201C15.8981 14.7215 16 14.3726 16 14V6C16 4.89543 15.1046 4 14 4H6ZM6 16H14C14.3692 16 14.7149 15.9 15.0118 15.7256L10.3504 11.1453C10.1559 10.9542 9.84409 10.9542 9.64956 11.1453L4.98824 15.7256C5.28505 15.9 5.63085 16 6 16Z"}
  end

  defp fluent_icon_path(:hourglass) do
    {"0 0 20 20",
     "M5.92188 18C5.66667 18 5.42448 17.9479 5.19531 17.8438C4.96615 17.7396 4.76042 17.599 4.57812 17.4219C4.39583 17.2448 4.25521 17.0417 4.15625 16.8125C4.05729 16.5833 4.00521 16.3385 4 16.0781C4 15.6719 4.04167 15.276 4.125 14.8906C4.20833 14.5052 4.33333 14.1328 4.5 13.7734C4.66667 13.4141 4.86979 13.0781 5.10938 12.7656C5.34896 12.4531 5.625 12.1641 5.9375 11.8984L7.75781 10.3828C7.8776 10.2786 7.9375 10.151 7.9375 10C7.9375 9.92708 7.92188 9.85677 7.89062 9.78906C7.85938 9.72135 7.8151 9.66406 7.75781 9.61719L5.9375 8.09375C5.30729 7.5625 4.82812 6.9401 4.5 6.22656C4.17188 5.51302 4.00521 4.74479 4 3.92188C4 3.66667 4.05208 3.42448 4.15625 3.19531C4.26042 2.96615 4.40104 2.76042 4.57812 2.57812C4.75521 2.39583 4.95833 2.25521 5.1875 2.15625C5.41667 2.05729 5.66146 2.00521 5.92188 2H14.0781C14.3333 2 14.5755 2.05208 14.8047 2.15625C15.0339 2.26042 15.2396 2.40104 15.4219 2.57812C15.6042 2.75521 15.7448 2.95833 15.8438 3.1875C15.9427 3.41667 15.9948 3.66146 16 3.92188C16 4.74479 15.8359 5.51302 15.5078 6.22656C15.1797 6.9401 14.6979 7.5625 14.0625 8.09375L12.2422 9.61719C12.1224 9.72135 12.0625 9.84896 12.0625 10C12.0625 10.0729 12.0781 10.1432 12.1094 10.2109C12.1406 10.2786 12.1849 10.3359 12.2422 10.3828L14.0625 11.8984C14.375 12.1589 14.651 12.4453 14.8906 12.7578C15.1302 13.0703 15.3307 13.4062 15.4922 13.7656C15.6536 14.125 15.7786 14.4974 15.8672 14.8828C15.9557 15.2682 16 15.6667 16 16.0781C16 16.3333 15.9479 16.5755 15.8438 16.8047C15.7396 17.0339 15.599 17.2396 15.4219 17.4219C15.2448 17.6042 15.0417 17.7448 14.8125 17.8438C14.5833 17.9427 14.3385 17.9948 14.0781 18H5.92188ZM14.0391 17C14.1693 17 14.2917 16.9766 14.4062 16.9297C14.5208 16.8828 14.625 16.8125 14.7188 16.7188C14.8125 16.625 14.8802 16.5234 14.9219 16.4141C14.9635 16.3047 14.9896 16.1797 15 16.0391C15 15.3776 14.8646 14.7578 14.5938 14.1797C14.3229 13.6016 13.9323 13.099 13.4219 12.6719L11.6016 11.1484C11.4297 11.0026 11.2969 10.8307 11.2031 10.6328C11.1094 10.4349 11.0625 10.224 11.0625 10C11.0625 9.77604 11.1094 9.5625 11.2031 9.35938C11.2969 9.15625 11.4297 8.98438 11.6016 8.84375L13.4219 7.32812C13.9271 6.90625 14.3151 6.40625 14.5859 5.82812C14.8568 5.25 14.9948 4.6276 15 3.96094C15 3.83073 14.9766 3.70833 14.9297 3.59375C14.8828 3.47917 14.8125 3.375 14.7188 3.28125C14.625 3.1875 14.5234 3.11979 14.4141 3.07812C14.3047 3.03646 14.1797 3.01042 14.0391 3H5.96094C5.82552 3 5.70052 3.02344 5.58594 3.07031C5.47135 3.11719 5.36979 3.1875 5.28125 3.28125C5.19271 3.375 5.125 3.47656 5.07812 3.58594C5.03125 3.69531 5.00521 3.82031 5 3.96094C5 4.28385 5.03385 4.60156 5.10156 4.91406C5.16927 5.22656 5.27344 5.52865 5.41406 5.82031C5.55469 6.11198 5.71875 6.38281 5.90625 6.63281C6.09375 6.88281 6.31771 7.11458 6.57812 7.32812L8.39844 8.84375C8.57031 8.98438 8.70312 9.15625 8.79688 9.35938C8.89062 9.5625 8.9375 9.77604 8.9375 10C8.9375 10.224 8.89062 10.4349 8.79688 10.6328C8.70312 10.8307 8.57031 11.0026 8.39844 11.1484L6.57812 12.6719C6.07292 13.0938 5.6849 13.5964 5.41406 14.1797C5.14323 14.763 5.00521 15.3828 5 16.0391C5 16.1745 5.02344 16.2995 5.07031 16.4141C5.11719 16.5286 5.1875 16.6302 5.28125 16.7188C5.375 16.8073 5.47656 16.875 5.58594 16.9219C5.69531 16.9688 5.82031 16.9948 5.96094 17H14.0391Z"}
  end

  defp fluent_icon_path(:shield) do
    {"0 0 20 20",
     "M9.72265 2.08397C9.8906 1.97201 10.1094 1.97201 10.2774 2.08397C12.2155 3.3761 14.3117 4.1823 16.5707 4.50503C16.817 4.54021 17 4.75117 17 5V9.5C17 13.3913 14.693 16.2307 10.1795 17.9667C10.064 18.0111 9.93605 18.0111 9.82051 17.9667C5.30699 16.2307 3 13.3913 3 9.5V5C3 4.75117 3.18296 4.54021 3.42929 4.50503C5.68833 4.1823 7.78446 3.3761 9.72265 2.08397ZM9.59914 3.34583C7.85275 4.39606 5.98541 5.09055 4 5.42787V9.5C4 12.892 5.96795 15.3634 10 16.9632C14.0321 15.3634 16 12.892 16 9.5V5.42787C14.0146 5.09055 12.1473 4.39606 10.4009 3.34583L10 3.09715L9.59914 3.34583Z"}
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # You can make use of gettext to translate error messages by
    # uncommenting and adjusting the following code:

    # if count = opts[:count] do
    #   Gettext.dngettext(TcgCheapWeb.Gettext, "errors", msg, msg, count, opts)
    # else
    #   Gettext.dgettext(TcgCheapWeb.Gettext, "errors", msg, opts)
    # end

    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
