# vim-llm

**vim-llm** is a Vim plugin that leverages an external LLM CLI tool to transform your file content using AI.
It sends the entire buffer to the LLM, cleans up code fences and whitespace issues from the generated output,
and then replaces your original file with the polished result.

## Features

- **Asynchronous Processing:** Utilizes [AsyncRun](https://github.com/skywind3000/asyncrun.vim) to run the LLM command without blocking Vim.
- **Smart Error Handling**: If the LLM command fails or returns no output, the plugin detects the issue, restores your original file, and automatically opens the quickfix window so you can view the error details.
- **Preview via Temp File:** Writes output to a temporary file while preserving the original file's extension (e.g. `file.llm-tmp.py`) for syntax highlighting.
- **Seamless Buffer Switching:** Opens the temporary file in the current buffer for live monitoring and automatically switches back to your original file when done.
- **Output Cleanup:** Automatically removes surrounding code fences, trims lines that contain only spaces (replacing them with empty strings), and cleans up any extra blank lines.
- **Easy to Use:** Just invoke the command with a prompt. For example:
  ```vim
  :LLMEdit 'add docstrings'
  ```

## Requirements

- **Vim 8+**
- [llm](https://github.com/simonw/llm) – for interacting with LLM.
- [AsyncRun.vim](https://github.com/skywind3000/asyncrun.vim) – for asynchronous command execution.

## Installation

If you're using [vim-plug](https://github.com/junegunn/vim-plug), add the following to your `~/.vimrc`:

```vim
Plug 'adiffpirate/vim-llm'
```

Then run:
```vim
:source ~/.vimrc
:PlugInstall
```

## Configuration

To set the LLM model, define the variable `g:llm_model` on your `~/.vimrc`.
If you don't define it or leave it empty, the -m flag will be omitted, and the LLM CLI will use its default model.
Example:
```vim
" Set the LLM model flag (optional). This flag will be passed as:
" -m <model> to the LLM CLI if defined.
let g:llm_model = 'qwen2.5-coder:14b'
```

Also, add this to your `~/.vimrc` to enable `autoread` so you can watch the LLM live editing:
```vim
" Enable autoread
set autoread
if ! exists("g:CheckUpdateStarted")
    let g:CheckUpdateStarted=1
    call timer_start(1,'CheckUpdate')
endif
function! CheckUpdate(timer)
    silent! checktime
    call timer_start(1000,'CheckUpdate')
endfunction
```

If you use the Airline plugin, add this to your `~/.vimrc` so you have a nice indicator when AsyncRun is executing:
```vim
let g:airline_section_warning = airline#section#create_right(['%{g:asyncrun_status == "running" ? "running cmd" : ""}'])
```

## Usage

Invoke the LLM transformation by running:

```vim
:LLMEdit 'your prompt here'
```

For example:
```vim
:LLMEdit 'add docstrings'
```

Your file will be processed by the LLM and replaced with its formatted version upon completion.

## License

[MIT](LICENSE)

## Contributing

Feel free to open issues or submit pull requests for improvements or bug fixes.

## Acknowledgments

Thanks to all contributors of LLM and AsyncRun.vim
