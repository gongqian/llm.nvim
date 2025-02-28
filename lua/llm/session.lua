local M = {}

local conf = require("llm.config")
local state = require("llm.state")
local streaming = require("llm.common.streaming")
local Popup = require("nui.popup")
local F = require("llm.common.func")
local LOG = require("llm.common.log")
local _layout = require("llm.common.layout")

function M.LLMSelectedTextHandler(description)
  local content = F.GetVisualSelection()
  state.popwin = Popup(conf.configs.popwin_opts)
  state.popwin:mount()
  state.session[state.popwin.winid] = {
    { role = "system", content = description },
    { role = "user", content = content },
  }

  vim.api.nvim_set_option_value("filetype", "llm", { buf = state.popwin.bufnr })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = state.popwin.bufnr })
  vim.api.nvim_set_option_value("spell", false, { win = state.popwin.winid })
  vim.api.nvim_set_option_value("wrap", true, { win = state.popwin.winid })
  vim.api.nvim_set_option_value("linebreak", false, { win = state.popwin.winid })
  state.llm.worker = streaming.GetStreamingOutput(
    state.popwin.bufnr,
    state.popwin.winid,
    state.session[state.popwin.winid],
    conf.configs.fetch_key,
    nil,
    nil,
    nil,
    nil,
    conf.configs.streaming_handler
  )

  for k, v in pairs(conf.configs.keys) do
    if k == "Session:Close" then
      F.WinMapping(state.popwin, v.mode, v.key, function()
        if state.llm.worker.job then
          state.llm.worker.job:shutdown()
          LOG:INFO("Suspend output...")
          vim.wait(200, function() end)
          state.llm.worker.job = nil
          vim.api.nvim_command("doautocmd BufEnter")
        end
        state.popwin:unmount()
      end, { noremap = true })
    elseif k == "Output:Cancel" then
      F.WinMapping(state.popwin, v.mode, v.key, F.CancelLLM, { noremap = true, silent = true })
    end
  end
end

function M.NewSession()
  if conf.session.status == -1 then
    local bufnr = vim.api.nvim_win_get_buf(0)
    local filename = vim.api.nvim_buf_get_name(bufnr)
    local winid = vim.api.nvim_get_current_win()

    if conf.configs.style == "float" then
      _layout.chat_ui()
      state.layout.popup:mount()
      vim.api.nvim_set_option_value("filetype", "llm", { buf = state.input.popup.bufnr })
      vim.api.nvim_set_current_win(state.input.popup.winid)
      vim.api.nvim_command("startinsert")
      bufnr = state.llm.popup.bufnr
      winid = state.llm.popup.winid

      -------------------------------------------------------------------------
      --- init current session
      -------------------------------------------------------------------------
      state.session.filename = "current"
      if not state.session[state.session.filename] then
        state.session[state.session.filename] = F.DeepCopy(conf.session.messages)
      end
      F.RefreshLLMText(state.session[state.session.filename])

      if conf.configs.save_session then
        local unmap_list = { "<Esc>", "<C-c>", "<CR>", "<Space>" }
        for _, v in ipairs(unmap_list) do
          state.history.popup:unmap("n", v)
        end
        state.history.popup = state.history.popup
      end

      -- set keymaps
      for k, v in pairs(conf.configs.keys) do
        if k == "Session:Close" then
          F.WinMapping(state.llm.popup, v.mode, v.key, function()
            F.CloseLLM()
            state.session = { filename = nil }
            conf.session.status = -1
            vim.api.nvim_command("doautocmd BufEnter")
          end, { noremap = true })
        elseif k == "Session:Toggle" then
          F.WinMapping(state.llm.popup, v.mode, v.key, F.ToggleLLM, { noremap = true })
        elseif k == "Focus:Input" then
          F.WinMapping(state.llm.popup, v.mode, v.key, function()
            vim.api.nvim_set_current_win(state.input.popup.winid)
            vim.api.nvim_command("startinsert")
          end, { noremap = true })
        end
      end

      for k, v in pairs(conf.configs.keys) do
        if k == "Input:Submit" then
          F.WinMapping(state.input.popup, v.mode, v.key, function()
            local input_table = vim.api.nvim_buf_get_lines(state.input.popup.bufnr, 0, -1, true)
            local input = table.concat(input_table, "\n")
            if not conf.configs.save_session then
              state.session.filename = "current"
              if not state.session[state.session.filename] then
                state.session[state.session.filename] = F.DeepCopy(conf.session.messages)
              end
            end
            vim.api.nvim_buf_set_lines(state.input.popup.bufnr, 0, -1, false, {})
            if input ~= "" then
              table.insert(state.session[state.session.filename], { role = "user", content = input })
              F.SetRole(bufnr, winid, "user")
              F.AppendChunkToBuffer(bufnr, winid, input)
              F.NewLine(bufnr, winid)
              vim.api.nvim_exec_autocmds("User", { pattern = "OpenLLM" })
            end
          end, { noremap = true })
        elseif k == "Input:Cancel" then
          F.WinMapping(state.input.popup, v.mode, v.key, F.CancelLLM, { noremap = true, silent = true })
        elseif k == "Input:Resend" then
          F.WinMapping(state.input.popup, v.mode, v.key, F.ResendLLM, { noremap = true, silent = true })
        elseif k == "Session:Close" then
          F.WinMapping(state.input.popup, v.mode, v.key, function()
            F.CloseLLM()
            state.session = { filename = nil }
            conf.session.status = -1
            vim.api.nvim_command("doautocmd BufEnter")
          end, { noremap = true })
        elseif k == "Session:Toggle" then
          F.WinMapping(state.input.popup, v.mode, v.key, F.ToggleLLM, { noremap = true })
        elseif conf.configs.save_session and k == "Input:HistoryNext" then
          F.WinMapping(state.input.popup, v.mode, v.key, function()
            F.MoveHistoryCursor(1)
          end, { noremap = true })
        elseif conf.configs.save_session and k == "Input:HistoryPrev" then
          F.WinMapping(state.input.popup, v.mode, v.key, function()
            F.MoveHistoryCursor(-1)
          end, { noremap = true })
        elseif k == "Focus:Output" then
          F.WinMapping(state.input.popup, v.mode, v.key, function()
            vim.api.nvim_set_current_win(state.llm.popup.winid)
            vim.api.nvim_command("stopinsert")
          end, { noremap = true })
        end
      end
      conf.session.status = 1
    else
      if filename ~= "" or vim.bo.modifiable == false then
        bufnr = vim.api.nvim_create_buf(false, true)
        local win_options = {
          split = conf.configs.style,
        }
        winid = vim.api.nvim_open_win(bufnr, true, win_options)
      end

      -- set keymaps
      for k, v in pairs(conf.configs.keys) do
        if k == "Output:Ask" then
          vim.keymap.set(v.mode, v.key, function()
            if state.input.popup then
              vim.api.nvim_set_current_win(state.input.popup.winid)
              vim.api.nvim_command("startinsert")
            else
              state.input.popup = Popup({
                relative = conf.configs.chat_ui_opts.input.split.relative,
                position = conf.configs.chat_ui_opts.input.split.position,
                enter = conf.configs.chat_ui_opts.input.split.enter,
                focusable = conf.configs.chat_ui_opts.input.split.focusable,
                zindex = conf.configs.chat_ui_opts.input.split.zindex,
                border = conf.configs.chat_ui_opts.input.split.border,
                win_options = conf.configs.chat_ui_opts.input.split.win_options,
                size = conf.configs.chat_ui_opts.input.split.size,
              })
              state.input.popup:mount()
              vim.api.nvim_set_option_value("filetype", "llm", { buf = state.input.popup.bufnr })
              vim.api.nvim_set_current_win(state.input.popup.winid)
              vim.api.nvim_command("startinsert")
              for name, d in pairs(conf.configs.keys) do
                if name == "Input:Submit" then
                  F.WinMapping(state.input.popup, d.mode, d.key, function()
                    local input_table = vim.api.nvim_buf_get_lines(state.input.popup.bufnr, 0, -1, true)
                    local input = table.concat(input_table, "\n")
                    state.session.filename = "current"
                    if not state.session[state.session.filename] then
                      state.session[state.session.filename] = F.DeepCopy(conf.session.messages)
                    end
                    state.input.popup:unmount()
                    state.input.popup = nil
                    if input ~= "" then
                      table.insert(state.session[state.session.filename], { role = "user", content = input })
                      F.SetRole(bufnr, winid, "user")
                      F.AppendChunkToBuffer(bufnr, winid, input)
                      F.NewLine(bufnr, winid)
                      vim.api.nvim_exec_autocmds("User", { pattern = "OpenLLM" })
                    end
                  end, { noremap = true })
                elseif name == "Session:Close" then
                  F.WinMapping(state.input.popup, d.mode, d.key, function()
                    F.CloseLLM()
                    conf.session.status = -1
                    vim.api.nvim_command("doautocmd BufEnter")
                  end, { noremap = true })
                elseif name == "Session:Toggle" then
                  F.WinMapping(state.input.popup, d.mode, d.key, F.ToggleLLM, { noremap = true })
                end
              end
            end
          end, { buffer = bufnr, noremap = true, silent = true })
        elseif k == "Output:Cancel" then
          vim.keymap.set(v.mode, v.key, F.CancelLLM, { buffer = bufnr, noremap = true, silent = true })
        elseif k == "Output:Resend" then
          vim.keymap.set(v.mode, v.key, F.ResendLLM, { buffer = bufnr, noremap = true, silent = true })
        end
      end
    end

    filename = os.date("/tmp/%Y%m%d-%H%M%S") .. ".llm"
    vim.api.nvim_set_option_value("filetype", "llm", { buf = bufnr })
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })
    vim.api.nvim_buf_set_name(bufnr, filename)
    vim.api.nvim_set_option_value("spell", false, { win = winid })
    vim.api.nvim_set_option_value("wrap", true, { win = winid })
    vim.api.nvim_set_option_value("linebreak", false, { win = winid })

    state.llm.bufnr = bufnr
    state.llm.winid = winid
  else
    F.ToggleLLM()
  end
end

return M
