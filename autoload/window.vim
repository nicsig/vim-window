fu! window#disable_wrap_when_moving_to_vert_split(dir) abort "{{{1
    call setwinvar(winnr('#'), '&wrap', 0)
    exe 'wincmd '.a:dir
    setl nowrap
    return ''
endfu

fu! s:get_terminal_buffer() abort "{{{1
    let buflist = tabpagebuflist(tabpagenr())
    call filter(buflist, {_,v -> getbufvar(v, '&bt', '') is# 'terminal'})
    return get(buflist, 0 , 0)
endfu

fu! window#navigate_or_resize(dir) abort "{{{1
    if get(s:, 'in_submode_window_resize', 0) | return window#resize(a:dir) | endif
    try
        exe 'wincmd '.a:dir
    catch
        return lg#catch_error()
    endtry
endfu

fu! window#preview_open() abort "{{{1
    " if we're already in the preview window, get back to previous window
    if &l:pvw
        wincmd p
        return
    endif

    " Try to display a possible tag under the cursor in a new preview window.
    try
        wincmd }
        wincmd P
        norm! zMzvzz
        wincmd p
    catch
        return lg#catch_error()
    endtry
endfu

fu! window#quit_everything() abort "{{{1
    try
        " We must force the wiping the terminal buffers if we want to be able to quit.
        if !has('nvim')
            let term_buffers = term_list()
            if !empty(term_buffers)
                exe 'bw! '.join(term_buffers)
            endif
        endif
        qall
    catch
        let exception = string(v:exception)
        call timer_start(0, {-> execute('echohl ErrorMsg | echo '.exception.' | echohl NONE', '')})
        "                                                         │
        "                         can't use `string(v:exception)` ┘
        "
        " …  because when  the timer  will be  executed `v:exception`  will be
        " empty; we  need to save `v:exception`  in a variable: any  scope would
        " probably works, but a function-local one is the most local.
        " Here, it works because a lambda can access its outer scope.
        " This seems to indicate that the callback of a timer is executed in the
        " context of the function where it was started.
    endtry
endfu

fu! window#resize(key) abort "{{{1
    let s:in_submode_window_resize = 1
    if exists('s:timer_id')
        call timer_stop(s:timer_id)
        unlet! s:timer_id
    endif
    let s:timer_id = timer_start(1000, {-> execute('let s:in_submode_window_resize = 0')})
    if a:key =~# '[hl]'
        " Why returning different keys depending on the position of the window?{{{
        "
        " `C-w <` moves a border of a vertical window:
        "
        "    - to the right, for the left border of the window on the far right
        "    - to the left, for the right border of other windows
        "
        " 2 reasons for these inconsistencies:
        "
        "    - Vim can't move the right border of the window on the far
        "      right, it would resize the whole “frame“, so it needs to
        "      manipulate the left border
        "
        "    - the left border of the  window on the far right is moved to
        "      the left instead of the right, to increase the visible size of
        "      the window, like it does in the other windows
        "}}}
        if lg#window#has_neighbor('right')
            let keys = a:key is# 'h'
                   \ ?     "\<c-w>3<"
                   \ :     "\<c-w>3>"
        else
            let keys = a:key is# 'h'
                   \ ?     "\<c-w>3>"
                   \ :     "\<c-w>3<"
        endif

    else
        if lg#window#has_neighbor('down')
            let keys = a:key is# 'k'
                   \ ?     "\<c-w>3-"
                   \ :     "\<c-w>3+"
        else
            let keys = a:key is# 'k'
                   \ ?     "\<c-w>3+"
                   \ :     "\<c-w>3-"
        endif
    endif

    call feedkeys(keys, 'in')
endfu

fu! window#scroll_preview(motion) abort "{{{1
    " TODO: support C-d and C-u motions (using `M-d` and `M-u` as the lhs of new keybindings?)
    " Maybe support `gg` and `G` too (`M-g M-g` and `M-g G`?).

    " don't do anything if there's no preview window
    if index(map(range(1, winnr('$')), {_,v -> getwinvar(v, '&pvw')}), 1) == -1
        return
    endif

    " go to preview window
    noa wincmd P

    " scroll
    let seq = {'j': 'j', 'k': 'k', 'h': '5zh', 'l': '5zl'}
    " Why do you open folds?{{{
    "
    " This is necessary when you sroll backward.
    "
    " Suppose you are  on the first line of  a fold and you move  one line back;
    " your cursor will *not* land on the previous line, but on the first line of
    " the previous fold.
    "}}}
    exe 'norm! zR'..seq[a:motion]
    " Do *not* merge the two `:norm!`.{{{
    "
    " If you're on the  last line and you try to scroll  forward, it would fail,
    " and the rest of the sequence (`zMzv`) would not be processed.
    " Same issue if you try to scroll backward while on the first line.
    "}}}
    norm! zMzv

    " get back to previous window
    noa wincmd p
endfu

fu! window#terminal_close() abort "{{{1
    let term_buffer = s:get_terminal_buffer()
    if term_buffer !=# 0
        noa call win_gotoid(bufwinid(term_buffer))
        " Why executing this autocmd?{{{
        "
        " In a terminal buffer, we disable the meta keys. When we give the focus
        " to another buffer, BufLeave is fired, and a custom autocmd restores the
        " meta keys.
        "
        " But if we're in the terminal window when we press `z>` to close it,
        " BufLeave hasn't been fired yet since the meta keys were disabled.
        "
        " So, they are not re-enabled. We need to make sure the autocmd is fired
        " before wiping the terminal buffer with `lg#window#quit()`.
        "}}}
        " Why checking its existence?{{{
        "
        " We don't install it in Neovim.
        "}}}
        if exists('#toggle_keysyms_in_terminal#bufleave')
            do toggle_keysyms_in_terminal BufLeave
        endif
        noa call lg#window#quit()
        noa wincmd p
    endif
endfu

fu! window#terminal_open() abort "{{{1
    let term_buffer = s:get_terminal_buffer()
    if term_buffer !=# 0
        let id = bufwinid(term_buffer)
        call win_gotoid(id)
        return
    endif

    let mod = lg#window#get_modifier()

    let how_to_open = has('nvim')
                  \ ?     mod.' split | terminal'
                  \ :     mod.' terminal'

    let resize = mod =~# '^vert'
             \ ?     ' | vert resize 30 | resize 30'
             \ :     ''

    exe printf('exe %s %s', string(how_to_open), resize)
endfu

fu! window#zoom_toggle() abort "{{{1
    if winnr('$') ==# 1
        return
    endif

    if exists('t:zoom_restore') && win_getid() ==# t:zoom_restore.winid
        exe get(t:zoom_restore, 'cmd', '')
        unlet t:zoom_restore
    else
        let t:zoom_restore = {'cmd': winrestcmd(), 'winid': win_getid()}
        wincmd |
        wincmd _
    endif
endfu

