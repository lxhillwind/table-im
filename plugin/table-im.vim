vim9script

# 码表输入法 FAQ {{{1
#
# 码表格式:
# - fcitx / 搜狗 / 手心输入法等的自定义短语格式;
# - (即 "code,seq=word" 例如 "wo,1=我"; 以非小写字母开头的行会被忽略)

# TODO 内置部分可以分发的码表方案 (目前只有 98 五笔)
#
# 为什么不...
# - 异步加载 table? 这样做会增加实现的复杂度.
#   (考虑加载 table 时输入了选词键这一情况)
# - 支持动态词库? 这样做使用 vim 来实现很可能碰到性能问题.
# - 支持其他格式的码表? 因为码表格式总是会变多的, 插件支持一种就够了,
#   其他来源格式可以通过外部程序转换. (参考文件 ../tables/wubi98-single.ini
#   前几行的注释)

# config {{{1

# 切换输入法的快捷键的字节码 (internal byte representation of keys):
# 可以使用 ":echo getcharstr()->keytrans()" 来获取按键对应的字面量, 再进行转义.
const im_toggle = exists('g:table_im#im_toggle') ? g:table_im#im_toggle : "\<C-\>"

# 码表文件的绝对路径: 默认为此仓库的 tables/wubi98-single.ini, 主要用作演示.
const table_file = exists('g:table_im#table_file') ? g:table_im#table_file : (
    fnamemodify(expand('<sfile>'), ':p:h:h') .. '/' .. 'tables/wubi98-single.ini'
)
# 键码元素范围
const code_element = exists('g:table_im#code_element') ? g:table_im#code_element : 'abcdefghijklmnopqrstuvwxyz'->split('\zs')
# 是否开启全码自动上屏 (对于 四码定长 的方案, 建议设置为 true)
const auto_commit = exists('g:table_im#auto_commit') ? g:table_im#auto_commit : false

# 是否使用 popup window 来显示候选窗口: 否则会使用 echo 来回显候选.
const using_popup = exists('g:table_im#using_popup') ? g:table_im#using_popup : true
# 候选字个数
const choice_num = range(1,
    exists('g:table_im#choice_num') ? g:table_im#choice_num : 5
)->mapnew((_, i) => string(i))

# 首选快捷键
const choice_first = exists('g:table_im#choice_first') ? g:table_im#choice_first : ' '->split('\zs')
# 次选快捷键
const choice_second = exists('g:table_im#choice_second') ? g:table_im#choice_second : ';'->split('\zs')
# 向前翻页
const choice_page_l = exists('g:table_im#choice_page_l') ? g:table_im#choice_page_l : '['->split('\zs')
# 向后翻页
const choice_page_r = exists('g:table_im#choice_page_r') ? g:table_im#choice_page_r : ']'->split('\zs')

# definition {{{1
const backspace = "\<Backspace>"
const enter = "\r"
const ctrl_h = "\<C-h>"
const ctrl_w = "\<C-w>"

# state {{{1
var input_sequence: string = ''
var im_state: bool = false
var page_number: number = 1
var popup_id = 0
var table_data = {} # init it lazily.
var table_data_is_inited = false

# impl {{{1

def ReadTable(): dict<dict<string>>
    # result structure:
    # {code: {seq: ch}}
    var result = {}
    for line in table_file->readfile()
        if match(line, '\v^[a-z]') < 0
            continue
        endif
        const i = line->matchlist('\v^([a-z]+)[,=]([0-9]+)[,=](.*)')
        const [code, seq, ch] = i[1 : 3]
        if !has_key(result, code)
            result[code] = {}
        endif
        result[code][seq] = ch
    endfor
    if auto_commit # {{{
        for [code, values] in result->items()
            if code->len() != 4
                continue
            endif
            var idx = 0
            var values_new = {}
            for ch in values->keys()->sort('n')->mapnew((_, i) => values[i])
                idx += 1
                values_new[idx->string()] = ch
            endfor
            result[code] = values_new
        endfor
    endif # }}}
    return result
enddef

def CleanInputSequence()
    if !empty(popup_id)
        popup_id->popup_close()
        popup_id = 0
    endif
    input_sequence = ''
    if !using_popup
        redrawstatus
    endif
enddef

const ch_empty = '_'
def RedrawInputSequence()
    if !!reg_executing()
        return
    endif
    const code = input_sequence
    var candidates_to_print = []
    if has_key(table_data, code)
        const candidates = table_data[code]
        const max_index = candidates->keys()->mapnew((_, i) => str2nr(i))->max()
        const page_max = ((max_index + 0.0) / choice_num->len())->ceil()->float2nr()
        if page_number > page_max
            page_number = page_max
        elseif page_number < 1
            page_number = 1
        endif
        const in_page_min = (page_number - 1) * choice_num->len() + 1
        const in_page_max = page_number * choice_num->len()
        for i in range(1, max_index)->mapnew((_, i) => string(i))
            if i->str2nr() > in_page_max || i->str2nr() < in_page_min
                continue
            endif
            candidates_to_print->add({seq: i, ch: candidates->get(i, ch_empty)})
        endfor
    endif
    var to_print = code
    for i in candidates_to_print
        var new_seq = i.seq->str2nr() % choice_num->len()
        if new_seq == 0
            new_seq = choice_num->len()
        endif
        to_print ..= $' {new_seq}: {i.ch}'
    endfor
    if !empty(popup_id)
        popup_id->popup_settext(to_print)
    else
        echo to_print
    endif
enddef

const handle_char = []
    ->extend(choice_num)
    ->extend(choice_first)
    ->extend(choice_second)
    ->extend(choice_page_l)
    ->extend(choice_page_r)
    ->extend(code_element)
    ->add(backspace)
    ->add(enter)
    ->add(ctrl_h)
    ->add(ctrl_w)
    ->add(im_toggle)

var enque_char = { state: false, char: '' }
def EnqueInputForNext(char: string)
    enque_char.state = true
    enque_char.char = char
enddef

def HandleInput(char: string): string
    # popup window ui {{{
    # close completion window when we input.
    if using_popup && pumvisible()
        # TODO handle 'completeopt'
        feedkeys("\<C-y>", 'n')
        # feedkeys again is necessary.
        feedkeys(char, 'm')
        return ''
    endif

    if using_popup
        if !empty(popup_id)
            # 如果开启全码上屏, 则当上一个全码有多个候选字时,
            # 顶其首字后需要手动关闭 popup window.
            popup_id->popup_close()
        endif
        const popup_max_length = choice_num->len() * 6 + 6  # some random length
        const screen_pos = screenpos(0, line('.'), col('.'))
        const pos_h = screen_pos.row < &lines - 7 ? 'top' : 'bot'
        const pos_v = screen_pos.col + 1 + popup_max_length < &columns ? 'left' : 'right'
        popup_id = popup_create('', {
            line: pos_h == 'top' ? 'cursor+1' : 'cursor-1',
            col:  pos_v == 'left' ? 'cursor+1' : &columns - 1,
            pos: $'{pos_h}{pos_v}',
            minheight: 1,
            maxheight: 1,
            minwidth: popup_max_length,
            maxwidth: popup_max_length,
            border: [],
        })
    endif
    # }}}

    input_sequence ..= char
    RedrawInputSequence()
    var result = ''
    while !empty(input_sequence)
        const ch = getcharstr()
        if handle_char->index(ch) >= 0
            if auto_commit && input_sequence->len() == 4 && code_element->index(ch) >= 0
                # 第5个字符让上一个全码首选上屏 {{{
                const word = table_data->get(input_sequence, {})->get('1')
                if !empty(word)
                    CleanInputSequence()
                    if !reg_executing()
                        EnqueInputForNext(ch)
                        return word
                    else
                        return word .. HandleInput(ch)
                    endif
                endif
            endif # }}}
            result = HandleInputInternal(ch)
        else
            const word = table_data->get(input_sequence, {})->get('1', '')
            CleanInputSequence()
            if ch == "\<Esc>"
                # 如果是 <Esc>, 则忽略候选字
                return ch
            endif
            return word .. ch
        endif
    endwhile
    CleanInputSequence()
    return result
enddef

def HandleInputInternal(char: string): string
    if code_element->index(char) >= 0
        # generate candidate
        page_number = 1
        input_sequence ..= char
        if auto_commit && input_sequence->len() == 4
            # 全码自动上屏 {{{
            if has_key(table_data, input_sequence)
                const choices = table_data[input_sequence]->values()
                if choices->len() == 1
                    defer CleanInputSequence()
                    return choices[0]
                endif
            endif
        endif # }}}
        RedrawInputSequence()
        return ''
    elseif char == backspace || char == ctrl_h
        page_number = 1
        # input_sequence won't be empty.
        if len(input_sequence) == 1
            CleanInputSequence()
        else
            input_sequence = input_sequence[ : len(input_sequence) - 2]
            RedrawInputSequence()
        endif
        return ''
    elseif char == enter
        defer CleanInputSequence()
        return input_sequence
    elseif char == ctrl_w
        CleanInputSequence()
        return ''
    elseif char == im_toggle
        defer CleanInputSequence()
        KeyBindingToggle()
        return input_sequence
    elseif choice_page_l->index(char) >= 0 || choice_page_r->index(char) >= 0
        if choice_page_l->index(char) >= 0
            page_number -= 1
        else
            page_number += 1
        endif
        RedrawInputSequence()
        return ''
    elseif ([]->extend(choice_num)->extend(choice_first)->extend(choice_second))->index(char) >= 0
        if input_sequence->empty()
            return char
        endif
        # select candidate
        var seq = '1'
        if choice_first->index(char) >= 0
            seq = '1'
        elseif choice_second->index(char) >= 0
            seq = '2'
        else
            seq = char
        endif
        seq = (
            seq->str2nr() + (page_number - 1) * choice_num->len()
        )->string()
        const code = input_sequence
        var selected = ''
        if has_key(table_data, code)
            if has_key(table_data[code], seq)
                selected = table_data[code][seq]
                CleanInputSequence()
            endif
        endif
        return selected
    endif
    return char
enddef

def KeyBindingSet()
    for i in code_element
        execute $'inoremap <expr> {i} HandleInput("{i}")'
    endfor
    if !table_data_is_inited
        table_data = ReadTable()
        table_data_is_inited = true
    endif
enddef

def KeyBindingUnset()
    for i in code_element
        execute $'iunmap {i}'
    endfor
    if !empty(popup_id)
        popup_id->popup_close()
        popup_id = 0
    endif
enddef

def ShowImState()
    const indicator = im_state ? '中' : 'EN'

    if using_popup
        const screen_pos = screenpos(0, line('.'), col('.'))
        const pos_h = screen_pos.row < &lines - 7 ? 'top' : 'bot'
        const pos_v = screen_pos.col < &columns / 2 ? 'left' : 'right'
        popup_notification(indicator, {
            line: pos_h == 'top' ? 'cursor+1' : 'cursor-1',
            col: pos_v == 'left' ? 'cursor+1' : 'cursor-1',
            pos: $'{pos_h}{pos_v}',
            minwidth: 2,
            time: 1000, highlight: 'Function',
        })
    else
        # TODO how to show indicator without popup window?
    endif
enddef

def KeyBindingToggle()
    if im_state
        KeyBindingUnset()
    else
        KeyBindingSet()
    endif
    im_state = !im_state
    if !reg_executing()
        ShowImState()
    endif
enddef

# magic {{{1

execute $'inoremap {im_toggle->keytrans()} <ScriptCmd>KeyBindingToggle()<CR>'

augroup table_im
    au!
    au InsertEnter * {
        CleanInputSequence()

        if !!reg_executing() || !!reg_recording()
            # reset state if using macro, for reproducable output.
            if im_state
                KeyBindingToggle()
            endif
        endif

        if !reg_executing() && table_data_is_inited
            ShowImState()
        endif
    }

    au CursorMovedI * {
        if !reg_executing()
            if enque_char.state
                enque_char.state = false
                timer_start(0, (_) => HandleInput(enque_char.char)->feedkeys('n'))
            endif
        endif
    }
augroup END
