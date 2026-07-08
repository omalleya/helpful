-- Disable netrw (required by nvim-tree)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

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
  { "ellisonleao/gruvbox.nvim", lazy = false, priority = 1000 },

  -- File explorer (replaces NERDTree)
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("nvim-tree").setup({
        view = { width = 20 },
        filters = { dotfiles = false },
      })
      vim.api.nvim_create_autocmd("VimEnter", {
        callback = function()
          require("nvim-tree.api").tree.open()
          vim.cmd("wincmd p")
        end,
      })
    end,
  },

  -- Fuzzy finder
  {
    "nvim-telescope/telescope.nvim",
    branch = "0.1.x",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = "Telescope",
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find files" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Live grep" },
      { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Buffers" },
      { "<leader>fr", "<cmd>Telescope oldfiles<cr>", desc = "Recent files" },
      { "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Help tags" },
    },
    opts = {
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
          "--no-ignore",
        },
        file_ignore_patterns = { "^%.git/" },
      },
      pickers = {
        find_files = {
          hidden = true,
          no_ignore = true,
        },
      },
    },
  },

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
      { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview: file history" },
      { "<leader>gH", "<cmd>DiffviewFileHistory<cr>", desc = "Diffview: repo history" },
      { "<leader>gc", "<cmd>DiffviewClose<cr>", desc = "Diffview: close" },
    },
    config = true,
  },

  -- Syntax highlighting (replaces vim-polyglot, yajs, vim-jsx)
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "master",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter.configs").setup({
        ensure_installed = {
          "javascript", "tsx", "typescript",
          "html", "css", "json",
          "lua", "vim", "vimdoc",
          "markdown", "markdown_inline",
          "bash",
        },
        highlight = { enable = true },
        indent = { enable = true },
      })

      -- Workaround for a Neovim 0.12 core bug: highlighting a markdown code
      -- fence crashes the injection engine ("attempt to call method 'range'").
      -- Inject only markdown_inline (keeps bold/links/code-spans), skip fenced
      -- code-block language injection that triggers the crash.
      vim.treesitter.query.set(
        "markdown",
        "injections",
        '((inline) @injection.content (#set! injection.language "markdown_inline"))'
      )
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
          "ts_ls",          -- TypeScript / JavaScript
          "gopls",          -- Go
          "rust_analyzer",  -- Rust
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
          vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, opts)
        end,
      })
    end,
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

-- Colorscheme
pcall(vim.cmd.colorscheme, "gruvbox")

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
