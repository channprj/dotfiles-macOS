set list
set listchars=nbsp:¬,tab:\|\ ,trail:␣,extends:>,precedes:<
hi SpecialKey ctermfg=darkgrey
set wrap
set nowrapscan
set ruler
set number
set fileencoding=utf-8
set tenc=utf-8
set hlsearch
set ignorecase
set tabstop=4
"set shiftwidth=4
set incsearch
set backspace=eol,start,indent
set history=1000
syntax on


call plug#begin('~/.vim/plugged')

""" PlugInstall List
Plug 'junegunn/vim-easy-align'
Plug 'junegunn/vim-github-dashboard'
"Plug 'junegunn/seoul256.vim'
Plug 'junegunn/goyo.vim'
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }

Plug 'powerline/powerline'
Plug 'sheerun/vim-polyglot'
Plug 'airblade/vim-gitgutter'
Plug 'davidhalter/jedi-vim'
Plug 'dracula/vim'
"let g:jedi#auto_initialization = 0

Plug 'ervandew/supertab'
Plug 'ntpeters/vim-better-whitespace'
"Plug 'nathanaelkane/vim-indent-guides'
"let g:indent_guides_enable_on_vim_startup = 1

"for fun
"Plug 'johngrib/vim-game-code-break'

call plug#end()

"colorscheme seoul256
"let g:seoul256_background=232

"colorscheme dracula
"colorscheme molokai
colorscheme onedark
if (has("termguicolors"))
  set termguicolors
endif

""" Powerline
"set rtp+=/Users/CHANN/.pyenv/versions/3.4.2/lib/python3.4/site-packages/powerline/bindings/vim
"let g:Powerline_symbols = 'fancy'
"set laststatus=2

""" fzf using Homebrew
set rtp+=/usr/local/opt/fzf

