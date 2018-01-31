if has("gui_running")
    set macligatures
endif
set guifont=Fira\ Code:h12
set ignorecase
set smartcase
set hlsearch
set incsearch
set magic
set showmatch
set noerrorbells
set novisualbell
set t_vb=
set tm=500
set shiftwidth=2
set tabstop=2
set ai "Auto indent
set si "Smart indent
set wrap "Wrap lines
set number
set backspace=indent,eol,start

let g:ctrlp_map = '<c-p>'
let g:ctrlp_cmd = 'CtrlP'

let g:user_emmet_leader_key='<Tab>'
let g:user_emmet_settings = {
  \  'javascript.jsx' : {
    \      'extends' : 'jsx',
    \  },
  \}

let g:ale_sign_error = '●' 
let g:ale_sign_warning = '.'
let g:ale_lint_on_enter = 0
let g:ale_fixers = {
\   'javascript': ['eslint'],
\}

call plug#begin('~/.vim/plugged')
Plug 'w0rp/ale'
Plug 'mxw/vim-jsx'
Plug 'pangloss/vim-javascript'
Plug 'ctrlpvim/ctrlp.vim'
Plug 'mattn/emmet-vim'
call plug#end()
