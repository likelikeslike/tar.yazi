--- @since 26.5.6

--- tar.yazi — archive selected files into <cwd>-<date>.tar.<ext>
--- Usage: plugin tar          (defaults to gz)
---        plugin tar -- gz    (gzip)
---        plugin tar -- zst   (zstd, faster + smaller)
---        plugin tar -- xz    (xz, slower + smallest)

-- Escape a literal string for use on the LHS of sed `s|...|...|` (BRE + `|` delimiter)
local function escape_sed(s)
  return (s:gsub("([%^%$%.%*%[%]%\\%|])", "\\%1"))
end

local read_selection = ya.sync(function()
  local paths = {}
  for _, u in pairs(cx.active.selected) do
    paths[#paths + 1] = tostring(u)
  end
  if #paths == 0 then
    local h = cx.active.current.hovered
    if h then
      paths[1] = tostring(h.url)
    end
  end
  return tostring(cx.active.current.cwd), paths
end)

return {
  entry = function(_, job)
    local fmt = (job.args and job.args[1]) or "gz"
    local flag, ext
    if fmt == "zst" then
      flag, ext = "--zstd", "tar.zst"
    elseif fmt == "xz" then
      flag, ext = "-J", "tar.xz"
    else
      flag, ext = "-z", "tar.gz"
    end

    local cwd, selected = read_selection()
    if #selected == 0 then
      ya.notify({ title = "tar", content = "No files selected", level = "warn", timeout = 3 })
      return
    end

    local dirname = cwd:match("([^/]+)/?$") or "archive"
    local archive = string.format("%s-%s.%s", dirname, os.date("%Y%m%d"), ext)

    -- gtar/tar strips leading `/` from absolute paths before applying --transform,
    -- so anchor on the cwd WITHOUT its leading slash to match the post-strip form.
    local args = { "--transform", string.format("s|^%s/||", escape_sed(cwd:sub(2))), flag, "-cvf", archive }
    for _, p in ipairs(selected) do
      args[#args + 1] = p
    end

    local tar_cmd = ya.target_os() == "macos" and "gtar" or "tar"
    local output, err = Command(tar_cmd):cwd(cwd):arg(args):stdout(Command.PIPED):stderr(Command.PIPED):output()
    if not output then
      ya.notify({
        title = "tar",
        content = "Failed to run " .. tar_cmd .. ": " .. tostring(err),
        level = "error",
        timeout = 5,
      })
      return
    end
    if output.status.code ~= 0 then
      ya.notify({ title = "tar failed", content = output.stderr or "unknown error", level = "error", timeout = 8 })
      return
    end
    ya.notify({ title = "tar", content = "Created " .. archive, level = "info", timeout = 4 })
  end,
}
