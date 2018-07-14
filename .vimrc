" Base settings
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
set expandtab
set smarttab
set ai "Auto indent
set si "Smart indent
set wrap "Wrap lines
set number
set backspace=indent,eol,start

" NERDTree
autocmd vimenter * NERDTree | wincmd p
autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTree") && b:NERDTree.isTabTree()) | q | endif
let NERDTreeAutoDeleteBuffer = 1
let NERDTreeShowHidden=1
let NERDTreeMinimalUI = 1
let NERDTreeDirArrows = 1
let NERDTreeWinSize = 20

" CtrlP
let g:ctrlp_map = '<c-p>'
let g:ctrlp_cmd = 'CtrlP'

" Emmet
let g:user_emmet_leader_key='<Tab>'
let g:user_emmet_settings = {
  \  'javascript.jsx' : {
    \      'extends' : 'jsx',
    \  },
  \}

" Ale
let g:ale_sign_error = '●' 
let g:ale_sign_warning = '.'
let g:ale_lint_on_enter = 0
let g:ale_fixers = {
\   'javascript': ['eslint'],
\}

" Plugins
call plug#begin('~/.vim/plugged')
Plug 'w0rp/ale'
Plug 'mxw/vim-jsx'
Plug 'ctrlpvim/ctrlp.vim'
Plug 'sheerun/vim-polyglot'
Plug 'mattn/emmet-vim'
Plug 'scrooloose/nerdtree'
Plug 'christoomey/vim-conflicted'
call plug#end()
