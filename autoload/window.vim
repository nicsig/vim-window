fu! window#disable_wrap_when_moving_to_vert_split(dir) abort "{{{1
    call setwinvar(winnr('#'), '&wrap', 0)
    exe 'wincmd '.a:dir
    setl nowrap
    return ''
endfu

fu! window#get_modifier_to_open_window() abort "{{{1
"   └─────┤
"         └ public so that it can be called in `vim-qf` (`qf#open()` in autoload/),
"           and in our vimrc
    let origin = winnr()

    " are we at the bottom of the tabpage?
    wincmd b
    if winnr() == origin
        let mod = 'botright'
    else
        wincmd p
        " or maybe at the top?
        wincmd t
        if winnr() == origin
            let mod = 'topleft'
        else
            " ok we're in a middle window
            wincmd p
            let mod = 'vert belowright'
        endif
    endif

    return mod
endfu

fu! window#navigate(dir) abort "{{{1
    try
        exe 'wincmd '.a:dir
    catch
    endtry
endfu

fu! window#open_preview(auto_close) abort "{{{1
    try
        exe "norm! \<c-w>}\<c-w>PzMzvzz\<c-w>p"
        if a:auto_close
            augroup close_preview_after_motion
                au!
                "              ┌─ don't use `<buffer>` because I suspect `CursorMoved`
                "              │  could happen in another buffer; example, after `gf`
                "              │  or sth similar
                "              │  we want the preview window to be closed no matter
                "              │  where the cursor moves
                "              │
                au CursorMoved * pclose
                              \| wincmd _
                              \| exe 'au! close_preview_after_motion'
                              \| aug! close_preview_after_motion
            augroup END
        endif
    catch
        return 'echoerr '.string(v:exception)
    endtry
    return ''
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

fu! window#scroll_preview(fwd) abort "{{{1
    if empty(filter(map(range(1, winnr('$')), 'getwinvar(v:val, "&l:pvw")'), 'v:val == 1'))
        sil! unmap <buffer> J
        sil! unmap <buffer> K
        sil! exe 'norm! '.(a:fwd ? 'J' : 'K')
    else
        if a:fwd
            "                ┌────── go to preview window
            "                │     ┌ scroll down
            "          ┌─────┤┌────┤
            exe "norm! \<c-w>P\<c-e>Lzv``\<c-w>p"
            "                       │└──┤└─────┤
            "                       │   │      └ get back to previous window
            "                       │   └ unfold and come back
            "                       └ go to last line of window
            "
            "                         in reality, we should do:
            "
            "                                 'L'.&so.'j'
            "
            "                         … but for some reason, when we reach the bottom of the window
            "                         the `j` motion makes it close automatically
        else
            exe "norm! \<c-w>P\<c-y>Hzv``\<c-w>p"
        endif
    endif
    return ''
endfu
