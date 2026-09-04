-- Low-memory profile detection: on small instances (e.g. 1GB VPS) skip the
-- heavyweight node-based LSP servers and AI completion. Everything else
-- (all-Lua plugins) stays — measured ~40MB total.
-- Override: NVIM_TINY=1 forces tiny, NVIM_TINY=0 forces full, regardless of RAM.
local M = {}

-- /proc/meminfo MemTotal in kB. NOTE: inside LXC/OpenVZ containers this
-- reports the HOST's memory — the cgroup limit below is the real ceiling.
local function meminfo_total_kb()
  if not vim.uv.fs_stat("/proc/meminfo") then
    return nil
  end
  local f = io.open("/proc/meminfo", "r")
  if not f then
    return nil
  end
  for line in f:lines() do
    local kb = line:match("^MemTotal:%s+(%d+)")
    if kb then
      f:close()
      return tonumber(kb)
    end
  end
  f:close()
  return nil
end

-- cgroup memory limit in bytes (v2 then v1). nil = no limit / not Linux.
local function cgroup_limit_bytes()
  for _, path in ipairs({
    "/sys/fs/cgroup/memory.max",                    -- cgroup v2
    "/sys/fs/cgroup/memory/memory.limit_in_bytes",  -- cgroup v1
  }) do
    local f = io.open(path, "r")
    if f then
      local v = f:read("*l")
      f:close()
      local n = tonumber(v)
      -- v2 says "max" when unlimited; v1 uses a huge sentinel (~2^63).
      -- Anything below 2^60 bytes is a real limit.
      if n and n > 0 and n < 2 ^ 60 then
        return n
      end
    end
  end
  return nil
end

-- The effective memory ceiling, in kB. min(MemTotal, cgroup limit) — on a
-- 1GB LXC container on a big host, the cgroup value is the truth.
local function effective_ram_kb()
  local ceiling = math.huge
  local meminfo = meminfo_total_kb()
  if meminfo then
    ceiling = math.min(ceiling, meminfo)
  end
  local cg = cgroup_limit_bytes()
  if cg then
    ceiling = math.min(ceiling, math.floor(cg / 1024))
  end
  if ceiling == math.huge then
    return nil
  end
  return math.floor(ceiling)
end

function M.tiny()
  if vim.env.NVIM_TINY == "1" then
    return true
  end
  if vim.env.NVIM_TINY == "0" then
    return false
  end
  if vim.fn.filereadable(vim.fn.stdpath("config") .. "/.tiny") == 1 then
    return true
  end
  local kb = effective_ram_kb()
  return kb ~= nil and kb < 2 * 1024 * 1024 -- under 2GB total RAM
end

return M
