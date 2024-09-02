# 码表输入法 FAQ {{{1

码表格式:
- fcitx / 搜狗 / 手心输入法等的自定义短语格式;
- (即 "code,seq=word" 例如 "wo,1=我"; 以非小写字母开头的行会被忽略)

TODO 内置部分可以分发的码表方案 (目前只有 98 五笔)

为什么不...
- 异步加载 table? 这样做会增加实现的复杂度.
  (考虑加载 table 时输入了选词键这一情况)
- 支持动态词库? 这样做使用 vim 来实现很可能碰到性能问题.
- 支持其他格式的码表? 因为码表格式总是会变多的, 插件支持一种就够了,
  其他来源格式可以通过外部程序转换. (参考文件 tables/wubi98-single.ini
  前几行的注释)

# config {{{1

```vim
# 切换输入法的快捷键的字节码 (internal byte representation of keys):
# 可以使用 ":echo getcharstr()->keytrans()" 来获取按键对应的字面量, 再进行转义.
const im_toggle = exists('g:table_im#im_toggle') ? g:table_im#im_toggle : "\<C-\>"

# 码表文件的绝对路径: 默认为此仓库的 tables/wubi98-single.ini, 主要用作演示.
const table_file = exists('g:table_im#table_file') ? g:table_im#table_file : (
    fnamemodify(expand('<sfile>'), ':p:h:h') .. '/' .. 'tables/wubi98-single.ini'
)
# 辅助码表文件的绝对路径 (使用 `#` 引导其中字词的编码): 默认为空.
const table_secnod = exists('g:table_im#table_second') ? g:table_im#table_second : ''
# 键码元素范围
const code_element = exists('g:table_im#code_element') ? g:table_im#code_element : 'abcdefghijklmnopqrstuvwxyz#'->split('\zs')
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
```

# LICENSE

- 插件代码使用 [MIT 协议](./LICENSE);

- 随本仓库分发的码表文件:
    - [./tables/wubi98-single.txt](./tables/wubi98-single.txt) 使用其原始授权 (公有领域). <https://github.com/fcitx/fcitx5-table-extra/tree/master/tables>
