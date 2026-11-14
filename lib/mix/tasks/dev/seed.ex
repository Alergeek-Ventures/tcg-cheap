defmodule Mix.Tasks.Dev.Seed do
  use Mix.Task

  @moduledoc """
  Fill this worktree's empty database with the data of another local one.

  A development server fetches shops and the catalogue only on request, so a
  new worktree starts without products. This copies the data instead of
  fetching it again.

      mix dev.seed [SOURCE_DATABASE_URL] [--target DATABASE_URL]

  The source defaults to the development database of the default-branch
  checkout (port 5436). The target is this worktree's `DATABASE_URL`; `--target`
  names another database, for example a scratch one.

  Nothing is changed unless the source is reachable, is not the target, has the
  same latest migration as the target and the target has no products yet (run
  `mix dev.reset` first to empty a worktree's database).

  Only data is copied, with `pg_dump` and `psql` from the devenv, in one
  transaction. Not copied:

    * the Oban tables, so the target starts without the source's jobs;
    * administrator accounts and sign-in tokens, which belong to one database;
    * the object storage tables (`storage_blobs`, `storage_attachments`,
      `storage_remote_images`): every worktree has its own S3 bucket, and these
      rows name objects only the source's bucket holds.

  Images: pages show placeholders at first. The copied products have their
  photo source cleared, so the mirror jobs of this worktree's server (every ten
  minutes) download the photos, and they register and download the card and
  logo images, again.

  Pages read the database, so no restart is needed.
  """
  alias Mix.Tasks.Dev.Shared

  @shortdoc "Copy another local database's data into this worktree's database"

  # The development database of the default-branch checkout (config/dev.exs).
  @default_source "ecto://postgres:postgres@localhost:5436/tcg_cheap_dev"

  @skipped_tables ~w(oban_* admins admin_auth_tokens storage_blobs storage_attachments storage_remote_images)
  @counted_tables ~w(sealed_products sealed_offers sealed_card_offers sealed_tcgdex_cards)

  # A copied product has no stored photo here: without this its photo source
  # would match the offer's photo and the mirror would never fetch it. The
  # table is qualified because the dump clears the search path.
  @reset_photo_sources "update public.sealed_products set photo_source_url = null, photo_attempted_at = null"

  @impl Mix.Task
  def run(args) do
    {opts, rest} = OptionParser.parse!(args, strict: [target: :string])
    env = Shared.load_env()

    source = connection(List.first(rest) || @default_source, "source")
    target = connection(opts[:target] || env["DATABASE_URL"], "target")
    tools = tools!()

    source_identity = query!(tools, source, "select #{identity_sql()}")
    target_identity = query!(tools, target, "select #{identity_sql()}")

    if source_identity == target_identity,
      do: Mix.raise("source and target are the same database")

    check_same_migration!(tools, source, target)
    check_target_empty!(tools, target)

    copy!(tools, source, target)
    report(tools, target)
  end

  defp identity_sql,
    do: "(select system_identifier from pg_control_system())::text || '/' || current_database()"

  defp tools! do
    Map.new(~w(pg_dump psql), fn name ->
      {name,
       System.find_executable(name) ||
         Mix.raise("#{name} was not found; run the task inside the devenv shell")}
    end)
  end

  # The password goes to the tools through PGPASSWORD, never on a command line
  # where `ps` shows it; the local databases use the fixed development login.
  defp connection(url, label) do
    case URI.parse(url || "") do
      %URI{scheme: scheme, host: host, path: "/" <> database, userinfo: userinfo} = uri
      when scheme in ["ecto", "postgres", "postgresql"] and is_binary(host) and database != "" ->
        {user, password} = credentials(userinfo)

        %{
          label: label,
          where: "#{host}:#{uri.port || 5432}/#{database}",
          args: [
            "--host=#{host}",
            "--port=#{uri.port || 5432}",
            "--username=#{user}",
            "--dbname=#{database}",
            "--no-password"
          ],
          env: [{"PGPASSWORD", password}]
        }

      _ ->
        Mix.raise(
          "the #{label} database URL is not a ecto://user:password@host:port/database URL"
        )
    end
  end

  defp credentials(nil), do: {"postgres", ""}

  defp credentials(userinfo) do
    case String.split(userinfo, ":", parts: 2) do
      [user, password] -> {user, URI.decode(password)}
      [user] -> {user, ""}
    end
  end

  defp query!(tools, conn, sql) do
    case System.cmd(
           tools["psql"],
           conn.args ++ ["--no-psqlrc", "--tuples-only", "--no-align", "-c", sql],
           env: conn.env,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        String.trim(output)

      {output, _status} ->
        Mix.raise("the #{conn.label} database #{conn.where} cannot be queried:\n#{output}")
    end
  end

  defp check_same_migration!(tools, source, target) do
    sql = "select max(version) from schema_migrations"
    {source_version, target_version} = {query!(tools, source, sql), query!(tools, target, sql)}

    if source_version != target_version do
      Mix.raise(
        "the databases are at different migrations (source #{source_version}, target #{target_version}); " <>
          "run mix ecto.migrate in the one that is behind"
      )
    end
  end

  defp check_target_empty!(tools, target) do
    if query!(tools, target, "select count(*) from sealed_products") != "0" do
      Mix.raise("the target already has products; run mix dev.reset first")
    end
  end

  defp copy!(tools, source, target) do
    dump = Path.join(System.tmp_dir!(), "dev-seed-#{System.unique_integer([:positive])}.sql")
    Mix.shell().info("Copying from #{source.where} to #{target.where}")

    try do
      run_tool!(tools["pg_dump"], source, [
        "--data-only",
        "--disable-triggers",
        "--exclude-schema=paradedb",
        "--exclude-schema=cron",
        "--exclude-table=schema_migrations",
        "--file=#{dump}"
        | Enum.map(@skipped_tables, &"--exclude-table=#{&1}")
      ])

      run_tool!(tools["psql"], target, [
        "--no-psqlrc",
        "--quiet",
        "--single-transaction",
        "--set=ON_ERROR_STOP=1",
        "--file=#{dump}",
        "--command=#{@reset_photo_sources}"
      ])
    after
      File.rm(dump)
    end
  end

  defp run_tool!(tool, conn, args) do
    case System.cmd(tool, conn.args ++ args, env: conn.env, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> Mix.raise("#{Path.basename(tool)} failed (exit #{status}):\n#{output}")
    end
  end

  defp report(tools, target) do
    Enum.each(@counted_tables, fn table ->
      Mix.shell().info("#{table}: #{query!(tools, target, "select count(*) from #{table}")}")
    end)

    Mix.shell().info(
      "Done. Pages read the database, so no restart is needed; photos and card images " <>
        "appear as the mirror jobs fetch them (every 10 minutes)."
    )
  end
end
