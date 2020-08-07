fu window#util#is_popup(...) abort "{{{1
    let n = a:0 ? win_getid(a:1) : win_getid()
    return win_gettype(n) is# 'popup'
endfu

fu window#util#latest_popup() abort "{{{1
    let popup_ids = popup_list()
    return max(popup_ids)
endfu

fu window#util#has_preview() abort "{{{1
    " Why is this a public function?{{{
    "
    " To be able to invoke it from the readline plugin (`readline#m_u#main()`).
    "}}}
    " What if we have a preview *popup*?{{{
    "
    " Then we want this function to return false, because when it's true, we use
    " `wincmd P`  to focus the  window, which fails  (`E441`) when the  tab page
    " only  contains a  preview popup.   For  Vim, a  preview popup  is *not*  a
    " preview window, even though it has the 'pvw' flag set.
    "
    " It turns out that `#has_preview()` *does* return false in that case.
    " That's because  – to find  the preview window –  it iterates over  all the
    " windows which have a number; a popup doesn't have a number (an id yes, but
    " number != id).
    "
    " So, the  function returns what  we want, even if  the preview window  is a
    " popup; all is good.
    "}}}
    return range(1, winnr('$'))->map({_, v -> getwinvar(v, '&pvw')})->index(1) >= 0
endfu

