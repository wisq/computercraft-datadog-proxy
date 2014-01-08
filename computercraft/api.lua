-- ex: ft=lua

-- Strongly adapted from statsd-ruby.

-- Sends an increment (count = 1) for the given stat to the
-- statsd server.  See 'count'.
function increment(stat, opts)
  count(stat, 1, opts)
end

-- Sends a decrement (count = -1) for the given stat to the
-- statsd server.  See 'count'.
function decrement(stat, opts)
  count(stat, -1, opts)
end

-- Sends an arbitrary count for the given stat to the statsd
-- server.
function count(stat, count, opts)
  send_stats(stat, count, 'c', opts)
end

-- Sends an arbitary gauge value for the given stat to the
-- statsd server.
--
-- This is useful for recording things like available disk
-- space, memory usage, and the like, which have different
-- semantics than counters.
function gauge(stat, value, opts)
  send_stats(stat, value, 'g', opts)
end

-- Sends an arbitary set value for the given stat to the
-- statsd server.
--
-- This is for recording counts of unique events, which are
-- useful to see on graphs to correlate to other values. For
-- example, a deployment might get recorded as a set, and be
-- drawn as annotations on a CPU history graph.
function set(stat, value, opts)
  send_stats(stat, value, 's', opts)
end

-- Internal functions:

function send_stats(stat, value, stat_type, opts)
  opts = opts or {}
  sample_rate = opts['sample_rate'] or 1.0
  tags = opts['tags'] or {}

  if sample_rate < 1.0 and math.random() > sample_rate then
    return false
  end

  local body =
    "s="  .. textutils.urlEncode(stat) ..
    "&t=" .. stat_type ..
    "&v=" .. value ..
    "&r=" .. sample_rate

  for k, v in pairs(tags) do
    body = body .. "&_" .. textutils.urlEncode(k) .. "=" .. v
  end

  http.request("http://127.0.0.1:9292", body)
  return true
end
