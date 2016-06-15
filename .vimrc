set wrap 
set nowrapscan 
set ruler
set number
set fileencoding=utf-8 
set tenc=utf-8
set hlsearch
set ignorecase
set tabstop=4
set shiftwidth=4 
set incsearch

syntax on 
colorscheme molokai 

set backspace=eol,start,indent 
set history=1000

call plug#begin('~/.vim/plugged')

""" PlugInstall List
Plug 'junegunn/vim-easy-align'
Plug 'junegunn/vim-github-dashboard'
Plug 'junegunn/seoul256.vim'
Plug 'powerline/powerline'
Plug 'junegunn/goyo.vim'
Plug 'davidhalter/jedi-vim'
"let g:jedi#auto_initialization = 0

Plug 'ervandew/supertab'

call plug#end()

""" seoul256 colorscheme
"let g:seoul256_background=232
colorscheme seoul256

""" Powerline
set rtp+=/Users/CHANN/.pyenv/versions/3.4.2/lib/python3.4/site-packages/powerline/bindings/vim
let g:Powerline_symbols = 'fancy'
set laststatus=2
