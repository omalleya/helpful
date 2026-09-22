-- Leader key (must be set before lazy.nvim)
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Options
vim.opt.clipboard = "unnamedplus"
vim.opt.wrap = true
vim.opt.linebreak = true
vim.opt.mouse = "a"
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.showmatch = true
vim.opt.errorbells = false
vim.opt.visualbell = false
vim.opt.timeoutlen = 500
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.expandtab = true
vim.opt.autoindent = true
vim.opt.smartindent = true
vim.opt.number = true
vim.opt.termguicolors = true
vim.opt.signcolumn = "yes"

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local out = vim.fn.system({
    "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath,
  })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
    }, true, {})
    return
  end
end
vim.opt.rtp:prepend(lazypath)

-- Plugins
require("lazy").setup({
  -- Keymap hints popup
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {
      spec = {
        { "<leader>f", group = "find" },
        { "<leader>h", group = "git hunks" },
        { "<leader>g", group = "diffview" },
        { "<leader>c", group = "code" },
      },
    },
  },

  -- Colorscheme
  -- { "ellisonleao/gruvbox.nvim", lazy = false, priority = 1000 },
  { "projekt0n/github-nvim-theme", lazy = false, priority = 1000 },

  -- File explorer
  {
    "nvim-mini/mini.files",
    lazy = false,
    dependencies = { "nvim-tree/nvim-web-devicons" },
    keys = {
      {
        "<leader>E",
        function()
          local files = require("mini.files")
          if vim.bo.filetype == "minifiles" then
            files.close()
            return
          end

          local path = vim.api.nvim_buf_get_name(0)
          files.open(path ~= "" and path or nil, false)
        end,
        desc = "Explore files",
      },
    },
    opts = {
      options = {
        permanent_delete = false,
        use_as_default_explorer = true,
      },
      windows = {
        preview = true,
        width_focus = 35,
        width_nofocus = 20,
        width_preview = 50,
      },
    },
  },

  -- Fuzzy finder: file finding via fff.nvim (Rust index, frecency),
  -- grep/buffers/recents/help via snacks.picker.
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    keys = {
      { "<leader>b", function() Snacks.picker.buffers() end, desc = "Buffers" },
      { "<leader>e", function() Snacks.explorer() end, desc = "Snacks explorer" },
      { "<leader>fg", function() Snacks.picker.grep() end, desc = "Grep" },
      { "<leader>fb", function() Snacks.picker.buffers() end, desc = "Buffers" },
      { "<leader>fr", function() Snacks.picker.recent() end, desc = "Recent files" },
      { "<leader>fh", function() Snacks.picker.help() end, desc = "Help tags" },
    },
    opts = {
      explorer = {
        replace_netrw = false,
        trash = true,
      },
      picker = {
        sources = {
          grep = {
            hidden = true,
            exclude = { "**/.git/**", "**/.worktrees/**", "**/node_modules/**" },
          },
          files = {
            hidden = true,
            exclude = { "**/.git/**", "**/.worktrees/**", "**/node_modules/**" },
          },
        },
      },
    },
  },

  {
    "dmtrKovalenko/fff.nvim",
    build = function()
      require("fff.download").download_or_build_binary()
    end,
    keys = {
      { "<leader>ff", function() require("fff").find_files() end, desc = "Find files" },
    },
    opts = {},
  },

  -- Telescope kept during snacks/fff trial; delete after 2026-09-17.
  --[[
  {
    "nvim-telescope/telescope.nvim",
    branch = "0.1.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-telescope/telescope-live-grep-args.nvim",
    },
    cmd = "Telescope",
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find files" },
      { "<leader>fg", "<cmd>Telescope live_grep_args<cr>", desc = "Live grep (args)" },
      { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Buffers" },
      { "<leader>fr", "<cmd>Telescope oldfiles<cr>", desc = "Recent files" },
      { "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Help tags" },
    },
    opts = function()
      local lga_actions = require("telescope-live-grep-args.actions")
      return {
        defaults = {
          vimgrep_arguments = {
            "rg",
            "--color=never",
            "--no-heading",
            "--with-filename",
            "--line-number",
            "--column",
            "--smart-case",
            "--hidden",
            "--glob",
            "!**/.git/**",
            "--glob",
            "!**/.worktrees/**",
            "--glob",
            "!**/node_modules/**",
          },
          file_ignore_patterns = { "^%.git/" },
        },
        pickers = {
          find_files = {
            find_command = {
              "rg",
              "--files",
              "--color=never",
              "--hidden",
              "--glob",
              "!**/.git/**",
              "--glob",
              "!**/.worktrees/**",
              "--glob",
              "!**/node_modules/**",
            },
          },
        },
        extensions = {
          live_grep_args = {
            auto_quoting = true,
            mappings = {
              i = {
                ["<C-k>"] = lga_actions.quote_prompt(),
                ["<C-g>"] = lga_actions.quote_prompt({ postfix = " -g " }),
              },
            },
          },
        },
      }
    end,
    config = function(_, opts)
      local telescope = require("telescope")
      telescope.setup(opts)
      telescope.load_extension("live_grep_args")
    end,
  },
  --]]

  -- Git: inline hunk signs, staging, blame
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      on_attach = function(bufnr)
        local gs = require("gitsigns")
        local function map(l, r, desc)
          vim.keymap.set("n", l, r, { buffer = bufnr, silent = true, desc = desc })
        end
        map("]c", function() gs.nav_hunk("next") end, "Next hunk")
        map("[c", function() gs.nav_hunk("prev") end, "Prev hunk")
        map("<leader>hs", gs.stage_hunk, "Stage hunk")
        map("<leader>hr", gs.reset_hunk, "Reset hunk")
        map("<leader>hS", gs.stage_buffer, "Stage buffer")
        map("<leader>hu", gs.undo_stage_hunk, "Undo stage hunk")
        map("<leader>hp", gs.preview_hunk, "Preview hunk")
        map("<leader>hb", function() gs.blame_line({ full = true }) end, "Blame line")
        map("<leader>hd", gs.diffthis, "Diff this")
      end,
    },
  },

  -- Git: full diff / branch review / file history / merge conflicts
  {
    "sindrets/diffview.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFocusFiles", "DiffviewFileHistory" },
    keys = {
      { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Diffview: working tree" },
      { "<leader>gb", function()
        local TYPE = "✎ Enter branch/ref…"
        local function open(base)
          base = base and vim.trim(base)
          if not base or base == "" then return end
          local mergeBase = vim.fn.systemlist("git merge-base " .. base .. " HEAD")[1]
          if vim.v.shell_error ~= 0 or not mergeBase or mergeBase == "" then
            vim.notify("No merge-base with " .. base, vim.log.levels.ERROR)
            return
          end
          vim.cmd("DiffviewOpen " .. mergeBase)
        end
        local branches = vim.fn.systemlist(
          "git for-each-ref --format='%(refname:short)' refs/heads refs/remotes"
        )
        if vim.v.shell_error ~= 0 then branches = {} end
        local present = {}
        for _, name in ipairs(branches) do present[vim.trim(name)] = true end
        local choices, seen = {}, {}
        local function add(name)
          if present[name] and name ~= "origin/HEAD" and not seen[name] then
            seen[name] = true
            choices[#choices + 1] = name
          end
        end
        for _, pref in ipairs({ "origin/master", "origin/main", "master", "main" }) do
          add(pref)
        end
        for _, name in ipairs(branches) do add(vim.trim(name)) end
        choices[#choices + 1] = TYPE
        vim.ui.select(choices, { prompt = "Diff branch since fork from:" }, function(choice)
          if not choice then return end
          if choice == TYPE then
            vim.ui.input({ prompt = "Diff against ref: " }, open)
          else
            open(choice)
          end
        end)
      end, desc = "Diffview: since fork from…" },
      { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview: file history" },
      { "<leader>gH", "<cmd>DiffviewFileHistory<cr>", desc = "Diffview: repo history" },
      { "<leader>gc", "<cmd>DiffviewClose<cr>", desc = "Diffview: close" },
    },
    config = true,
  },

  -- Syntax highlighting (replaces vim-polyglot, yajs, vim-jsx)
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      local parsers = {
        "javascript", "tsx", "typescript",
        "html", "css", "json",
        "lua", "vim", "vimdoc",
        "markdown", "markdown_inline",
        "bash",
      }
      require("nvim-treesitter").install(parsers)

      vim.api.nvim_create_autocmd("FileType", {
        pattern = {
          "javascript", "javascriptreact", "typescript", "typescriptreact",
          "html", "css", "json",
          "lua", "vim", "vimdoc", "markdown", "bash", "sh",
        },
        callback = function(args)
          if pcall(vim.treesitter.start, args.buf) then
            vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })
    end,
  },

  -- Formatting
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    keys = {
      { "<leader>cf", function() require("conform").format({ async = true }) end, desc = "Format buffer" },
    },
    opts = {
      formatters_by_ft = {
        javascript = { "eslint_d", "eslint", stop_after_first = true },
        javascriptreact = { "eslint_d", "eslint", stop_after_first = true },
        typescript = { "eslint_d", "eslint", stop_after_first = true },
        typescriptreact = { "eslint_d", "eslint", stop_after_first = true },
      },
      format_on_save = {
        timeout_ms = 500,
        lsp_format = "fallback",
      },
    },
  },

  -- Linting
  {
    "mfussenegger/nvim-lint",
    event = { "BufWritePost", "InsertLeave" },
    config = function()
      require("lint").linters_by_ft = {
        javascript = { "eslint_d" },
        javascriptreact = { "eslint_d" },
        typescript = { "eslint_d" },
        typescriptreact = { "eslint_d" },
      }
      vim.api.nvim_create_autocmd({ "BufWritePost", "InsertLeave" }, {
        callback = function()
          require("lint").try_lint()
        end,
      })
    end,
  },

  -- LSP servers (Python, TypeScript, Go, Rust, Swift)
  { "mason-org/mason.nvim", config = true },
  {
    "mason-org/mason-lspconfig.nvim",
    dependencies = {
      "mason-org/mason.nvim",
      "neovim/nvim-lspconfig",
    },
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = {
          "pyright",        -- Python
          "vtsls",          -- TypeScript / JavaScript
          "gopls",          -- Go
          "rust_analyzer",  -- Rust
        },
      })

      -- vtsls tuned for large monorepos (loancrate). watchOptions is the
      -- load-bearing fix: default per-file watching hit ~21k live watchers
      -- and crashed tsserver; watch parent dirs instead. maxTsServerMemory is
      -- sized for a 128GB machine running several worktrees at once.
      vim.lsp.config("vtsls", {
        settings = {
          typescript = {
            tsserver = {
              maxTsServerMemory = 24576,
              watchOptions = {
                watchFile = "useFsEventsOnParentDirectory",
              },
            },
          },
          vtsls = {
            experimental = {
              completion = {
                enableServerSideFuzzyMatch = true,
              },
            },
          },
        },
      })

      -- Swift / Objective-C (sourcekit-lsp ships with Xcode, not via Mason).
      -- Uses xcode-build-server's buildServer.json for .xcodeproj/.xcworkspace projects.
      vim.lsp.enable("sourcekit")

      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local opts = { buffer = args.buf, silent = true }
          vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
          vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
          vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
          vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
          vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
          vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
          vim.keymap.set("n", "[d", function() vim.diagnostic.jump({ count = -1 }) end, opts)
          vim.keymap.set("n", "]d", function() vim.diagnostic.jump({ count = 1 }) end, opts)
          vim.keymap.set("n", "<leader>cd", vim.diagnostic.open_float, opts)
        end,
      })
    end,
  },

  -- Completion
  {
    "saghen/blink.cmp",
    version = "1.*",
    event = "InsertEnter",
    opts = {
      keymap = { preset = "enter" },
      completion = {
        list = { selection = { preselect = false } },
      },
      sources = {
        default = { "lsp", "path", "buffer" },
      },
    },
  },

  -- Surround motions (ys/cs/ds)
  { "kylechui/nvim-surround", event = "VeryLazy", config = true },

  -- Seamless nvim <-> tmux pane navigation (pairs with tmux.conf C-hjkl)
  {
    "alexghergh/nvim-tmux-navigation",
    event = "VeryLazy",
    opts = {},
    keys = {
      { "<C-h>", "<cmd>NvimTmuxNavigateLeft<cr>", desc = "Navigate left" },
      { "<C-j>", "<cmd>NvimTmuxNavigateDown<cr>", desc = "Navigate down" },
      { "<C-k>", "<cmd>NvimTmuxNavigateUp<cr>", desc = "Navigate up" },
      { "<C-l>", "<cmd>NvimTmuxNavigateRight<cr>", desc = "Navigate right" },
    },
  },

  -- Emmet (kept — still the best option)
  {
    "mattn/emmet-vim",
    ft = { "html", "css", "javascript", "javascriptreact", "typescriptreact" },
    init = function()
      vim.g.user_emmet_leader_key = "<Tab>"
      vim.g.user_emmet_settings = {
        ["javascript.jsx"] = { extends = { "jsx", "js" } },
      }
    end,
  },
})

-- Ask-agent questions: visually select code, hit <leader>q, type the question
-- into the popover, <Enter> to submit. Appends file path, line range, snippet,
-- and question to AGENT-QUESTIONS.md at the repo root, for a coding agent to
-- answer later.
local function ask_agent_question()
  local start_line = vim.fn.line("v")
  local end_line = vim.fn.line(".")
  if start_line > end_line then
    start_line, end_line = end_line, start_line
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local selected = vim.api.nvim_buf_get_lines(bufnr, start_line - 1, end_line, false)
  local filetype = vim.bo[bufnr].filetype
  local abs_path = vim.api.nvim_buf_get_name(bufnr)
  local root = vim.fs.root(bufnr, ".git") or vim.fn.getcwd()
  local rel_path = abs_path
  if abs_path:sub(1, #root + 1) == root .. "/" then
    rel_path = abs_path:sub(#root + 2)
  end
  local location = ("%s:%d-%d"):format(rel_path, start_line, end_line)
  local out_path = root .. "/AGENT-QUESTIONS.md"

  vim.cmd([[execute "normal! \<Esc>"]])

  local question_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[question_buf].bufhidden = "wipe"
  local question_win = vim.api.nvim_open_win(question_buf, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = math.min(70, vim.o.columns - 4),
    height = 3,
    style = "minimal",
    border = "rounded",
    title = " Ask about " .. location .. " ",
    title_pos = "left",
    footer = " <Enter> submit · <Esc><Esc> cancel ",
    footer_pos = "right",
  })
  vim.cmd.startinsert()

  local function close_popover()
    vim.cmd.stopinsert()
    if vim.api.nvim_win_is_valid(question_win) then
      vim.api.nvim_win_close(question_win, true)
    end
  end

  local function submit()
    local question_lines = vim.api.nvim_buf_get_lines(question_buf, 0, -1, false)
    local question = vim.trim(table.concat(question_lines, " "))
    close_popover()
    if question == "" then
      return
    end
    local out = io.open(out_path, "a")
    if out == nil then
      vim.notify("Could not open " .. out_path, vim.log.levels.ERROR)
      return
    end
    out:write(("\n## %s\n\n%s\n\n```%s\n%s\n```\n"):format(
      location, question, filetype, table.concat(selected, "\n")
    ))
    out:close()
    vim.notify("Question logged: " .. location)
  end

  local map_opts = { buffer = question_buf, silent = true }
  vim.keymap.set({ "i", "n" }, "<CR>", submit, map_opts)
  vim.keymap.set("n", "<Esc>", close_popover, map_opts)
end

vim.keymap.set("x", "<leader>q", ask_agent_question, { desc = "Ask agent about selection" })

-- Colorscheme
-- pcall(vim.cmd.colorscheme, "gruvbox")
pcall(vim.cmd.colorscheme, "github_dark")

-- Diagnostic signs
vim.diagnostic.config({
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "●",
      [vim.diagnostic.severity.WARN] = ".",
      [vim.diagnostic.severity.INFO] = ".",
      [vim.diagnostic.severity.HINT] = ".",
    },
  },
})
