-- Low-memory profile detection: on small instances (e.g. 1GB VPS) skip the
-- heavyweight node-based LSP servers and AI completion. Everything else
-- (all-Lua plugins) stays — measured ~40MB total.
-- Override: NVIM_TINY=1 forces tiny, NVIM_TINY=0 forces full, regardless of RAM.
local M = {}

local function total_ram_kb()
  if vim.uv.fs_stat("/proc/meminfo") then
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
  local out = vim.fn.system("sysctl -n hw.memsize 2>/dev/null")
  local bytes = tonumber(vim.fn.trim(out))
  if bytes then
    return math.floor(bytes / 1024)
  end
  return nil
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
  local kb = total_ram_kb()
  return kb ~= nil and kb < 2 * 1024 * 1024 -- under 2GB total RAM
end

return M
