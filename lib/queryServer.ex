defmodule Spider.QueryServer do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(Spider.QueryServer, { %{} }, opts)
  end

  @impl true
  def init(state) do
    HTTPoison.start()

    schedule_next()

    {:ok, state}
  end

  defp add_url(project, url, depth) do
    newDepth = Integer.to_string(String.to_integer(depth) + 1)
    Spider.QueueAgent.add_url_to_queue({ project, url, newDepth })
  end

  defp get_all_commands(project) do
    { _, commands } = Spider.CommandAgent.get_all_items(project)
    commands
  end

  defp extract_text(project, url, document) do
    commands = get_all_commands(project)

    regexCommands = Enum.filter(commands, fn command ->
      cond do
        command =~ ~r/^regex:/i -> true
        true -> false
      end
    end)

    strippedCommands = Enum.map(regexCommands, fn command ->
      %{ "regex" => regex, "select" => select, "filter" => filter } = Map.merge(%{ "regex" => ".*", "select" => "", "filter" => "" }, Jason.decode!(String.slice(command, 6, String.length(command) - 6)))
      { Regex.compile(regex, "i") |> elem(1), select, Regex.compile(filter, "i") |> elem(1) }
    end)

    Enum.reduce(strippedCommands, %{}, fn t, acc ->
      { regex, select, filter } = t
      # apply our selection (if any)
      text = cond do
        select != "" -> Floki.find(document, select) |> Floki.text()
        true -> Floki.find(document, "body") |> Floki.text()
      end

      # first check to see if the URL passes our filter
      cond do
        url =~ filter -> Map.merge(Regex.named_captures(regex, text), acc)
        true -> %{}
      end
    end)
  end

  defp extract_link(project, link, depth, host) do
    { _, attrs, children } = link
    title = cond do
      length(children) == 0 -> ""
      true -> hd(children)
    end
    [{ "href", href }] = Enum.filter(attrs, fn x ->
      { name, _ } = x
      case name do
        "href" -> true
        _ -> false
      end
    end)
    %URI{host: hrefHost} = URI.parse(href)
    cond do
      hrefHost == nil -> :ok
      String.downcase(hrefHost) == String.downcase(host) and should_see(project, href) -> add_url(project, href, depth)
      true -> :ok
    end
    %{ "title" => cond do
      is_binary(title) -> title
      true -> ""
    end, "href" => href }
  end

  defp extract_hx(hx) do
    { _, _, children } = hx
    title = cond do
      length(children) == 0 -> ""
      true -> hd(children)
    end
    %{ "title" => cond do
      is_binary(title) -> title
      true -> ""
    end }
  end

  defp parse_body(project, url, depth, body) do

    IO.puts("Processing " <> url)

    %URI{host: host} = URI.parse(url)

    {:ok, document} = Floki.parse_document(body)

    links = Enum.map(Floki.find(document, "a[href]"), fn link ->
      extract_link(project, link, depth, host)
    end)

    contextual_links = Enum.uniq(Enum.map(Floki.find(document, "article a[href]"), fn link ->
      extract_link(project, link, depth, host)
    end) ++ Enum.map(Floki.find(document, "p a[href]"), fn link ->
      extract_link(project, link, depth, host)
    end))

    images = Enum.uniq(Enum.map(Floki.find(document, "img[src]"), fn image ->
      { _, attrs, _ } = image
      [{ "src", href }] = Enum.filter(attrs, fn x ->
        { name, _ } = x
        case name do
          "src" -> true
          _ -> false
        end
      end)
      altAttrs = Enum.filter(attrs, fn x ->
        { name, _ } = x
        case name do
          "alt" -> true
          _ -> false
        end
      end)
      [{ "alt", alt }] = cond do
        length(altAttrs) > 0 -> altAttrs
        true -> [{"alt", ""}]
      end
      %{ "alt" => cond do
        is_binary(alt) -> alt
        true -> ""
      end, "src" => href }
    end))

    h1s = Enum.map(Floki.find(document, "h1"), fn h1 ->
      extract_hx(h1)
    end)

    h2s = Enum.map(Floki.find(document, "h2"), fn h2 ->
      extract_hx(h2)
    end)

    h3s = Enum.map(Floki.find(document, "h3"), fn h3 ->
      extract_hx(h3)
    end)

    canonical_urls = Enum.map(Floki.find(document, "link[rel='canonical']"), fn link ->
      { _, attrs, _ } = link
      hrefAttrs = Enum.filter(attrs, fn x ->
        { name, _ } = x
        case name do
          "href" -> true
          _ -> false
        end
      end)
      [{ "href", href }] = cond do
        length(hrefAttrs) > 0 -> hrefAttrs
        true -> [{"href", ""}]
      end
      href
    end)

    [canonical_url | _] = cond do
      length(canonical_urls) > 0 -> canonical_urls
      true -> [""]
    end

    title = Floki.text(Floki.find(document, "title"))

    allText = Floki.find(document, "body") |> Floki.text()

    wordCount = allText |> String.downcase() |> String.split() |> length()

    timestamp = DateTime.now("Etc/UTC") |> elem(1) |> DateTime.to_iso8601

    %{ "canonical_url" => canonical_url, "extracted_text" => extract_text(project, url, document), "images" => images, "contextual_links" => contextual_links, "links" => links, "title" => title, "h1s" => h1s, "h2s" => h2s, "h3s" => h3s, "hash" => String.downcase(Base.encode16(:crypto.hash(:sha256,body))), "timestamp" => timestamp, "word_count" => wordCount, "depth" => depth }
  end

  defp should_see_internal(project, url) do
    seen = Enum.map(Spider.SeenAgent.get_all_items_in_queue(project), &elem(&1, 1))

    firstUri = URI.parse(url)
    length(Enum.filter(seen, fn secondUri ->
      case secondUri do
        %URI{ host: host } when host == "" -> true
        _ -> cond do
              (firstUri.host != nil and secondUri.host != nil and
               String.trim(String.downcase(firstUri.host)) == String.trim(String.downcase(secondUri.host))) -> cond do
                (firstUri.path != nil and secondUri.path != nil and
                 String.trim(String.downcase(firstUri.path)) == String.trim(String.downcase(secondUri.path))) -> cond do
                  (firstUri.query != nil and secondUri.query != nil and
                   String.trim(String.downcase(firstUri.query)) == String.trim(String.downcase(secondUri.query))) -> true
                  firstUri.query == nil and secondUri.query == nil -> true
                  true -> false
                end
                firstUri.path == nil and secondUri.path == nil -> true
                (firstUri.path == "/" and secondUri.path == nil) or (firstUri.path == nil and secondUri.path == "/") -> true
                true -> false
               end
              true -> false
            end
      end
    end)) == 0
  end

  defp should_see(project, url) do
    commands = get_all_commands(project)

    inclusionCommands = Enum.filter(commands, fn command ->
      cond do
        command =~ ~r/^include:/i -> true
        true -> false
      end
    end)

    inclusionCommandsExecuted = Enum.filter(inclusionCommands, fn command ->
      cond do
        url =~ Regex.compile(String.slice(command, 8, String.length(command) - 8), "i") |> elem(1) -> true
        true -> false
      end
    end)

    exclusionCommands = Enum.filter(commands, fn command ->
      cond do
        command =~ ~r/^exclude:/i -> true
        true -> false
      end
    end)

    exclusionCommandsExecuted = Enum.filter(exclusionCommands, fn command ->
      cond do
        url =~ Regex.compile(String.slice(command, 8, String.length(command) - 8), "i") |> elem(1) -> true
        true -> false
      end
    end)

    cond do
      length(exclusionCommands) > 0 -> cond do
        length(exclusionCommandsExecuted) > 0 -> false
        true -> should_see_internal(project, url)
      end
      length(inclusionCommands) > 0 -> cond do
        length(inclusionCommandsExecuted) > 0 and length(exclusionCommandsExecuted) == 0 -> should_see_internal(project, url)
        true -> false
      end
      true -> should_see_internal(project, url)
    end
  end

  defp add_redirect(project, url, depth, statusCode, headers) do
    { _, redirectTo } = hd(Enum.filter(headers, fn header ->
      case header do
        { "Location", _ } -> true
        _ -> false
      end
    end))

    timestamp = DateTime.now("Etc/UTC") |> elem(1) |> DateTime.to_iso8601

    Spider.OutgoingAgent.add_data_to_queue(
      project,
      %{
        "url" => url,
        "data" => %{
          "status_code" => statusCode,
          "body" => %{ "canonical_url" => "", "extracted_text" => [], "images" => [], "contextual_links" => [], "links" => [], "title" => "", "h1s" => [], "h2s" => [], "h3s" => [], "hash" => "", "timestamp" => timestamp, "word_count" => 0, "depth" => depth },
          "headers" => extract_headers(headers)
        }
      })

    add_url(project, redirectTo, depth)
  end

  defp extract_headers(headers) do
    Enum.map(Enum.filter(headers, fn header ->
      cond do
        elem(header, 0) =~ ~r/last-modified/i -> true
        elem(header, 0) =~ ~r/content-type/i -> true
        elem(header, 0) =~ ~r/content-length/i -> true
        true -> false
      end
    end), fn tuple -> Tuple.to_list(tuple) end)
  end

  defp tick(state, project, url, depth) do
    response = case url do
      url when url != "" -> {:ok, %{ "url" => url, "response" => HTTPoison.get!(url, ["User-Agent": "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"]) } }
      _ -> {:no_url}
    end

    cond do
      url != "" -> Spider.SeenAgent.add_data_to_queue(project, URI.parse(url))
      true -> {:ok}
    end

    case response do
      {:ok, %{ "url" => _, "response" => %HTTPoison.Error{reason: reason}}} -> IO.puts(reason)
      {:ok, %{ "url" => _, "response" => %HTTPoison.Response{status_code: 301, headers: headers}}} ->
        add_redirect(project, url, depth, 301, headers)
      {:ok, %{ "url" => _, "response" => %HTTPoison.Response{status_code: 302, headers: headers}}} ->
        add_redirect(project, url, depth, 302, headers)
      {:ok, %{ "url" => _, "response" => %HTTPoison.Response{body: body, status_code: status_code, headers: headers}}} ->
        Spider.OutgoingAgent.add_data_to_queue(project,
          %{
            "url" => url,
            "data" => %{
              "status_code" => status_code,
              "body" => parse_body(project, url, depth, body),
              "headers" => extract_headers(headers)
            }
          })
      {:no_url} -> :ok
    end

    state
  end

  def process_control_flow_cmds(state, urlData) do
    { project, url, depth } = urlData

    commands = get_all_commands(project)

    newState = cond do
      Enum.any?(commands, fn x -> x == "halt" end) -> state
      true -> (Spider.QueueAgent.get_next_in_queue(); tick(state, project, url, depth))
    end

    schedule_next()

    {:noreply, newState}
  end

  @impl true
  def handle_info(:tick, state) do
    urlData = Spider.QueueAgent.peek_next_in_queue()

    cond do
      urlData == {"", "", ""} -> (schedule_next(); {:noreply, state})
      true -> process_control_flow_cmds(state, urlData)
    end
  end

  defp schedule_next do
    Process.send_after(self(), :tick, 3000)
  end
end
