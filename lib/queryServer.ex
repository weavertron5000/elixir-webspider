defmodule Spider.QueryServer do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(Spider.QueryServer, { [] }, opts)
  end

  @impl true
  def init(state) do
    HTTPoison.start()

    schedule_next()

    {:ok, state}
  end

  defp add_url(url) do
    Spider.QueueAgent.add_url_to_queue(url)
  end

  defp parse_body(url, body, state) do

    IO.puts("Processing " <> url)

    %URI{host: host} = URI.parse(url)
    {:ok, document} = Floki.parse_document(body)
    links = Enum.map(Floki.find(document, "a[href]"), fn link ->
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
        String.downcase(hrefHost) == String.downcase(host) and should_see(href, state) -> add_url(href)
        true -> :ok
      end
      %{ "title" => cond do
        is_binary(title) -> title
        true -> ""
      end, "href" => href }
    end)

    images = Enum.map(Floki.find(document, "img[src]"), fn image ->
      { _, attrs, _ } = image
      [{ "src", href }] = Enum.filter(attrs, fn x ->
        { name, _ } = x
        case name do
          "src" -> true
          _ -> false
        end
      end)
      [{ "alt", alt }] = Enum.filter(attrs, fn x ->
        { name, _ } = x
        case name do
          "alt" -> true
          _ -> false
        end
      end)
      %{ "alt" => cond do
        is_binary(title) -> title
        true -> ""
      end, "src" => href }
    end)

    h1s = Enum.map(Floki.find(document, "h1"), fn h1 ->
      { _, _, children } = h1
      title = cond do
        length(children) == 0 -> ""
        true -> hd(children)
      end
      %{ "title" => cond do
        is_binary(title) -> title
        true -> ""
      end }
    end)

    h2s = Enum.map(Floki.find(document, "h2"), fn h2 ->
      { _, _, children } = h2
      title = cond do
        length(children) == 0 -> ""
        true -> hd(children)
      end
      %{ "title" => cond do
        is_binary(title) -> title
        true -> ""
      end }
    end)

    h3s = Enum.map(Floki.find(document, "h3"), fn h3 ->
      { _, _, children } = h3
      title = cond do
        length(children) == 0 -> ""
        true -> hd(children)
      end
      %{ "title" => cond do
        is_binary(title) -> title
        true -> ""
      end }
    end)

    [canonical_url | _] = Enum.map(Floki.find(document, "link[rel='canonical']"), fn link ->
      { _, attrs, _ } = link
      [{ "href", href }] = Enum.filter(attrs, fn x ->
        { name, _ } = x
        case name do
          "href" -> true
          _ -> false
        end
      end)
      href
    end)

    title = Floki.text(Floki.find(document, "title"))

    wordCount = Floki.find(document, "body") |> Floki.text() |> String.downcase() |> String.split() |> length()

    timestamp = DateTime.now("Etc/UTC") |> elem(1) |> DateTime.to_iso8601

    %{ "canonical_url" => canonical_url, "images" => images, "links" => links, "title" => title, "h1s" => h1s, "h2s" => h2s, "h3s" => h3s, "hash" => String.downcase(Base.encode16(:crypto.hash(:sha256,body))), "timestamp" => timestamp, "word_count" => wordCount }
  end

  defp should_see(url, state) do
    { seen } = state
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

  defp add_redirect(url, statusCode, headers) do
    { _, redirectTo } = hd(Enum.filter(headers, fn header ->
      case header do
        { "Location", _ } -> true
        _ -> false
      end
    end))

    timestamp = DateTime.now("Etc/UTC") |> elem(1) |> DateTime.to_iso8601

    Spider.OutgoingAgent.add_data_to_queue(
      %{
        "url" => url,
        "data" => %{
          "status_code" => statusCode,
          "body" => %{ "canonical_url" => "", "images" => [], "links" => [], "title" => "", "h1s" => [], "h2s" => [], "h3s" => [], "hash" => "", "timestamp" => timestamp, "word_count" => 0 },
          "headers" => extract_headers(headers)
        }
      })

    add_url(redirectTo)
  end

  defp extract_headers(headers) do
    Enum.filter(headers, fn header ->
      cond do
        elem(header, 0) =~ ~r/last-modified/i -> true
        elem(header, 0) =~ ~r/content-type/i -> true
        elem(header, 0) =~ ~r/content-length/i -> true
        true -> false
      end
    end)
  end

  defp tick(state) do
    { seen } = state

    url = Spider.QueueAgent.get_next_in_queue()

    response = case url do
      url when url != "" -> {:ok, %{ "url" => url, "response" => HTTPoison.get(url, ["User-Agent": "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"]) } }
      _ -> {:no_url}
    end

    newState = case url do
      url when url != "" -> { seen ++ [URI.parse(url)]}
      _ -> state
    end

    case response do
      {:ok, %{ "url" => _, "response" => %HTTPoison.Error{reason: reason}}} -> IO.puts(reason)
      {:ok, %{ "url" => _, "response" => %HTTPoison.Response{status_code: 301, headers: headers}}} ->
        add_redirect(url, 301, headers)
      {:ok, %{ "url" => _, "response" => %HTTPoison.Response{status_code: 302, headers: headers}}} ->
        add_redirect(url, 302, headers)
      {:ok, %{ "url" => url, "response" => %HTTPoison.Response{body: body, status_code: status_code, headers: headers}}} ->
        Spider.OutgoingAgent.add_data_to_queue(
          %{
            "url" => url,
            "data" => %{
              "status_code" => status_code,
              "body" => parse_body(url, body, newState),
              "headers" => extract_headers(headers)
            }
          })
      {:no_url} -> :ok
    end

    newState
  end

  @impl true
  def handle_info(:tick, state) do
    commands = Spider.CommandAgent.get_all_items()

    newState = cond do
      Enum.any?(commands, fn x -> x == "halt" end) -> state
      true -> tick(state)
    end

    schedule_next()

    {:noreply, newState}
  end

  defp schedule_next do
    Process.send_after(self(), :tick, 5000)
  end
end
