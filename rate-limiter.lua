--[[
Rate limiter tool (redis script) using CAS (check-and-set).

This script supports a series of limiters and simple ban punishment.
The inputs consists of three parts:
  - key_prefix
  - event_id
  - limiters_str

`key_prefix` and `event_id` are composed into redis key (see `get_ban_key` and `get_count_key`)
`limiters_str` is a json string which can be decoded into an array, with items in this format:
  {
    period: number, time in seconds,
    limit: number,
    punishment (optional): number, time in seconds,
  }

- For every limiter, no more than `limit` events can pass.
- If only the event passed all limiters, the event can pass.
- If the event passed all limiters and the `counter` equals `limit` and there is any punishment, ban this event with maximum of all punishments of limiters.
--]]

local key_prefix, event_id, limiters_str = unpack(KEYS)
local limiters = cjson.decode(limiters_str)


local function check_limit(count, limiter)
    -- reject
    if count >= limiter.limit then
        return { result=false }
    end
    -- resolve, but could punish if all passed all checks
    if count == limiter.limit - 1 then
        return { result=true, punishment=limiter.punishment }
    end
    -- resolve
    return { result=true, value=count }
end

local function get_ban_key()
    return string.format('%s:%s:ban', key_prefix, event_id)
end
local function get_count_key(limiter)
    return string.format('%s:%s-%s', key_prefix, event_id, limiter.period)
end


-- check if banned
local ban_key = get_ban_key()
local ban_key_ttl = redis.call('ttl', ban_key)
if ban_key_ttl > 0 then  -- banned
    return cjson.encode({ success=false, reason='BANNED' })
end

-- not banned, check all limiters
local punishment = 0
local operations = {}
for _, limiter in ipairs(limiters) do
    local key = get_count_key(limiter)
    local count = tonumber(redis.call('get', key)) or 0
    local ret = check_limit(count, limiter)
    -- being rejected of any limiter results in rejection of the event
    if ret.result == false then
        return cjson.encode({ success=false, reason='LIMITED' })
    end
    -- to get the maximum punishment
    if type(ret.punishment) == 'number' and ret.punishment > punishment then
        punishment = ret.punishment
    end
end

-- passed, increment all counters
for _, limiter in ipairs(limiters) do
    local key = get_count_key(limiter)
    local incrementedCounter = redis.call('incr', key)
    table.insert(operations, { op='incr', key=key, result=incrementedCounter })
    -- first set, set ttl
    if incrementedCounter == 1 then
        redis.call('expire', key, limiter.period)
        table.insert(operations, { op='expire', key=key })
    end
end
-- set punishment
if punishment > 0 then
    redis.call('setex', ban_key, punishment, punishment)  -- value is meaningless now
    table.insert(operations, { op='ban', ban_key=ban_key })
end


return cjson.encode({ success=true, operations=operations, punishment=punishment })
