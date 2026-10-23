-- Run through measure-blank-rows.sh, using -c (not -l, which does not draw wraps).
local function emit(fd, text)
  local stream = fd == 2 and io.stderr or io.stdout
  stream:write(text .. '\n')
  stream:flush()
end

local function main()
  local corpus = vim.json.decode(table.concat(vim.fn.readfile(assert(vim.env.CORPUS)), '\n'))
  local widths = vim.split(assert(vim.env.WIDTHS), ' ', { trimempty = true })
  local oracle = vim.env.ORACLE == '1'
  vim.opt.rtp:prepend(assert(vim.env.YMD_ROOT))
  vim.o.termguicolors = true
  vim.o.shortmess = vim.o.shortmess .. 'AIF'
  vim.o.scrolloff = 0
  vim.o.shadafile = 'NONE'
  vim.o.modeline = false
  -- Only the known config warning is quiet; failed conceal fails its file.
  local notify, ymd_error = vim.notify, nil
  vim.notify = function(message, ...)
    if type(message) ~= 'string' then
      return notify(message, ...)
    end
    if not message:match('^%[ymd%]') then
      return emit(2, message)
    end
    if message:match('^%[ymd%] Invalid pattern') then
      if vim.env.VERBOSE == '1' then
        emit(2, message)
      end
    elseif message:lower():find('error', 1, true) then
      ymd_error = ymd_error or message
    else
      emit(2, message)
    end
  end
  local function finish_render()
    vim.wait(0)
    if ymd_error then
      error(ymd_error, 0)
    end
  end
  require('ymd').setup()
  local bm = require('ymd.buffer_manager')
  local numw = 6
  local max_lines = 1000

  local function visible_width(buf, row, text)
    local hidden, extra = {}, 0
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, { row, 0 }, { row, -1 }, { details = true })) do
      local d = mark[4]
      if d.conceal ~= nil and d.end_row == row and d.end_col then
        for byte = mark[3] + 1, d.end_col do
          hidden[byte] = true
        end
        extra = extra + vim.fn.strdisplaywidth(d.conceal)
      end
      if d.virt_text and d.virt_text_pos == 'inline' then
        for _, chunk in ipairs(d.virt_text) do
          extra = extra + vim.fn.strdisplaywidth(chunk[1])
        end
      end
    end
    local kept = {}
    for byte = 1, #text do
      if not hidden[byte] then
        kept[#kept + 1] = text:sub(byte, byte)
      end
    end
    return vim.fn.strdisplaywidth(table.concat(kept)) + extra
  end

  local function count_file(path, width)
    local fd, reason = vim.uv.fs_open(path, 'r', 0)
    assert(fd, reason)
    vim.uv.fs_close(fd)
    vim.cmd('silent edit! ' .. vim.fn.fnameescape(path))
    local buf = vim.api.nvim_get_current_buf()
    assert(vim.fn.filereadable(path) == 1, 'file is not readable')
    -- A blank guard lets the first real line be measured with the cursor above
    -- it. It exists only in this unsaved buffer; reports subtract the guard.
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, { '' })
    vim.bo[buf].filetype = 'markdown'
    bm.attach(buf)
    bm.render(buf)
    finish_render()
    vim.wo.wrap, vim.wo.number, vim.wo.relativenumber = true, true, false
    vim.wo.numberwidth, vim.wo.signcolumn, vim.wo.foldcolumn = numw, 'no', '0'
    vim.wo.foldenable = false
    local textoff = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].textoff
    -- Width is the text area, independently of the gutter's actual width.
    vim.o.columns = width + textoff
    if vim.o.columns ~= width + textoff then
      emit(2, ('ERR --widths: requested %d text columns, Neovim set %d'):format(width, vim.o.columns - textoff))
      return nil, nil, 2
    end
    local nlines = vim.api.nvim_buf_line_count(buf)
    local blank, hits, top, counted = 0, {}, 1, 1
    while counted < nlines do
      vim.api.nvim_win_set_cursor(0, { top, 0 })
      bm.update_revealed_row(buf)
      finish_render()
      vim.fn.winrestview({ topline = top, lnum = top, col = 0, skipcol = 0 })
      -- Finish injected-language conceal before drawing; an async parse can
      -- otherwise leave markup visible and make counts depend on machine load.
      assert(vim.treesitter.get_parser(buf)):parse(true)
      vim.cmd('redraw!')
      local cur, first, last, filler = nil, nil, nil, false
      local candidates, drawn = {}, {}
      for row = 1, vim.api.nvim_win_get_height(0) do
        local gutter = ''
        for col = 1, textoff do
          gutter = gutter .. vim.fn.screenstring(row, col)
        end
        local number = tonumber(gutter:match('%d+'))
        if number then
          cur, last, first = number, number, first or number
          drawn[number] = 1
        elseif gutter:match('^%s*~') then
          filler = true
          break
        elseif cur then
          drawn[cur] = drawn[cur] + 1
          local cells = ''
          for col = textoff + 1, textoff + width do
            cells = cells .. vim.fn.screenstring(row, col)
          end
          if cells:match('^%s*$') then
            candidates[cur] = candidates[cur] or {}
            candidates[cur][row] = true
          end
        end
      end
      assert(first and first >= top, 'page did not draw its requested top line')
      -- conceal_lines may hide every buffer line after the last drawn one.
      local through = filler and nlines or last - 1
      if through <= top and not filler then
        assert(vim.o.lines < max_lines,
          ('cannot complete the page at line %d within %d screen rows'):format(top, vim.api.nvim_win_get_height(0)))
        vim.o.lines = math.min(vim.o.lines * 2, max_lines)
      else
        for line = math.max(top + 1, counted + 1), through do
          if drawn[line] and (not oracle or candidates[line]) then
            local text = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1]
            local need = math.max(1, math.ceil(visible_width(buf, line - 1, text) / width))
            if not oracle and need > drawn[line] then
              emit(2, ('ERR %s:%d: visible-width estimate exceeds rows drawn'):format(path, line - 1))
              return nil, nil, 1
            end
            local blanks = candidates[line] and vim.tbl_count(candidates[line]) or 0
            local count = math.min(math.max(0, drawn[line] - need), blanks)
            if count > 0 then
              blank = blank + count
              hits[#hits + 1] = { line - 1, count }
            end
          end
        end
        counted, top = math.max(counted, through), through
      end
    end
    vim.cmd('bwipeout!')
    return blank, hits
  end

  local version_lines = vim.split(vim.fn.execute('version'), '\n', { trimempty = true })
  local version = 'nvim ' .. version_lines[1]:gsub('^NVIM ', '')
    .. ' (' .. (vim.fn.execute('version'):match('Build type: (%S+)') or 'unknown') .. ')'
  local result = { version = version, counts = {}, hits = {} }
  if not oracle then
    emit(1, version .. ' | ' .. #corpus .. ' files')
  end
  for _, w in ipairs(widths) do
    local width, total, hits = tonumber(w), 0, {}
    vim.o.columns, vim.o.lines = width + numw, 400
    for _, path in ipairs(corpus) do
      vim.fn.writefile({ width .. '\t' .. path }, assert(vim.env.PROGRESS))
      if vim.env.VERBOSE == '1' then
        emit(2, ('measuring width %d: %s'):format(width, path))
      end
      local ok, count, where, code = pcall(count_file, path, width)
      if not ok then
        emit(2, 'ERR ' .. path .. ': ' .. tostring(count))
        return 1
      end
      if code then
        return code
      end
      total = total + count
      for _, hit in ipairs(where) do
        hits[#hits + 1] = { width, path, hit[1], hit[2] }
      end
    end
    result.counts[#result.counts + 1] = total
    vim.list_extend(result.hits, hits)
    if not oracle then
      emit(1, ('width %3d: %d blank rows'):format(width, total))
      for _, hit in ipairs(hits) do
        emit(1, ('  %s:%d (%d blank rows)'):format(hit[2], hit[3], hit[4]))
      end
    end
  end
  vim.fn.writefile({ vim.json.encode(result) }, assert(vim.env.OUT))
  return 0
end

local ok, code = pcall(main)
if not ok then
  emit(2, 'ERR measurement: ' .. tostring(code))
  code = 1
end
vim.cmd(code == 0 and 'qa!' or 'cquit ' .. code)
