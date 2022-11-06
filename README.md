# nvim-dinkeys

Dynamically set `indentkeys` using tree-sitter. Think of this as [JoosepAlviste/nvim-ts-context-commentstring](https://github.com/JoosepAlviste/nvim-ts-context-commentstring) for `indentkeys` option. Useful for auto indent in injection tree like codeblock in markdown.

**NOTE**: This plugin assumes the `indentkeys` setting are the same for files with same filetype.

## Setup

```lua
require('dinkeys').setup({
    -- filetypes to enable, can also be a funtion
    enable = { "markdown" },
    -- whether to disable indentkeys cache for the buffer, can also be a function
    disable_cache = false,
    -- events of detecting langauge change
    events = { "InsertEnter", "CursorMoved" },
    -- events of writing cache to file
    write_events = { "ExitPre" },
    debounce = 200,
})
```
