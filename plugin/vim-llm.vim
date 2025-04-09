" =============================================================================
" AI LLM Vim Plugin
" Author: adiffpirate
" Description: Transform current file using an LLM. The plugin
"              sends the file content to the LLM via the llm CLI tool,
"              writes output to a temporary file (with preserved extension),
"              cleans the result (removes code fences and trims whitespace-only
"              lines), then replaces the original file contents.
" Requirements: llm CLI, AsyncRun.vim
" =============================================================================

" -----------------------------------------------------------------------------
" Guard to avoid double-loading the plugin
" -----------------------------------------------------------------------------
if exists("g:loaded_ai_llm_plugin")
  finish
endif
let g:loaded_ai_llm_plugin = 1

" -----------------------------------------------------------------------------
" Command: :LLM 'your prompt here'
" Description: Start AI transformation based on a user-provided prompt.
" -----------------------------------------------------------------------------
command! -nargs=1 LLMEdit call LLMEditRun(<f-args>)

" -----------------------------------------------------------------------------
" Function: LLMEditRun(prompt)
" Description: Builds the LLM shell command, generates a cleaned prompt,
"              writes output to a temp file, and triggers callback.
" -----------------------------------------------------------------------------
function! LLMEditRun(user_prompt) abort
  if a:user_prompt == ''
    echoerr '❌ You must provide a prompt. Usage: :LLM ''your prompt'''
    return
  endif

  let l:orig_file = expand('%:p')
  if l:orig_file == ''
    echoerr '❌ Could not get current file path.'
    return
  endif

  " Create tmp file with extension preserved (e.g. file.llm-tmp.py)
  let l:tmp_file = substitute(l:orig_file, '\(\.[^.]*\)$', '.llm-tmp\1', '')

  " Save paths globally for callback use
  let g:llm_tmp_file = l:tmp_file
  let g:llm_orig_file = l:orig_file

  " Build prompt from heredoc
  let l:prompt_lines =<< trim PROMPT
You are an Senior Software Engineer expert in multiple languages.

Your only task is to output raw code as plain text. Do not include, in any way:
    - Code fences (e.g., \`\`\`language)
    - Headings
    - Explanations
    - Comments
    - Any non-code text

Write the code as plain text, preserving the exact indentation and formatting conventions of the requested or existing snippet.
Add meaningful comments, docstrings and similars, to improve code readbility. So resulting code should be easy for humans to maintain and understand.

Do not ask for clarifications, do not request interactions, and do not make any assumptions outside the scope of the provided input below.
If the input is incomplete or ambiguous, generate the most logical and functional code based on the given context.

INSTRUCTION: {user_prompt}

Use the initial code from input whose filepath is {file} as baseline and context, and determine the language based on the file extension.
If no initial code was provided that means you should generate from scratch based on the instruction above.
PROMPT

  let l:prompt = join(l:prompt_lines, "\n")
  let l:prompt = substitute(l:prompt, '{user_prompt}', a:user_prompt, '')
  let l:prompt = substitute(l:prompt, '{file}', l:orig_file, '')

  " Optional LLM model flag:
  " If g:llm_model is defined and non-empty, use it with the -m flag.
  if exists('g:llm_model') && !empty(g:llm_model)
    let l:model_flag = '-m ' . g:llm_model . ' '
  else
    let l:model_flag = ''
  endif

  " Build the llm shell command.
  let l:cmd = 'cat ' . shellescape(l:orig_file)
        \ . ' | llm ' . l:model_flag
        \ . '-s ' . shellescape(l:prompt)
        \ . ' | tee ' . shellescape(l:tmp_file)

  " Pre-create and open the temp file in the current buffer to avoid W13 warning and allow live watching
  call writefile([], l:tmp_file)
  execute 'edit! ' . fnameescape(l:tmp_file)
  setlocal buftype=
  setlocal noswapfile
  setlocal readonly
  setlocal nomodified

  " Start the AsyncRun command with callback
  execute 'AsyncRun -post=call\ LLMTransformCallback() ' . l:cmd
endfunction

" -----------------------------------------------------------------------------
" Function: LLMTransformCallback()
" Description: Cleans code fences and whitespace-only lines from generated file,
"              replaces original file content, deletes tmp, restores buffer.
" -----------------------------------------------------------------------------
function! LLMTransformCallback() abort
  let l:tmp_file = get(g:, 'llm_tmp_file', '')
  let l:orig_file = get(g:, 'llm_orig_file', '')

  " Check if the temp file is empty
  if getfsize(l:tmp_file) <= 0
    " Delete temp file
    call delete(l:tmp_file)
    " Reload original file
    execute 'edit ' . fnameescape(l:orig_file)
    " Open quickfix window to show command output
    execute 'noautocmd botright copen 20'
    " Print error alert and exit
    echoerr "❌ LLM command failed. Check your model or llm CLI."
  endif

  let l:lines = readfile(l:tmp_file)

  " Remove first and last code fences
  if len(l:lines) > 0 && l:lines[0] =~ '^```'
    call remove(l:lines, 0)
  endif
  if len(l:lines) > 0 && l:lines[-1] =~ '^```'
    call remove(l:lines, -1)
  endif

  " Remove last line if it's empty
  if len(l:lines) > 0 && l:lines[-1] =~ '^\s*$'
    call remove(l:lines, -1)
  endif

  " Replace lines that are only whitespace with an empty string
  let l:new_lines = []
  for l in l:lines
    if l =~ '^\s\+$'
      call add(l:new_lines, '')
    else
      call add(l:new_lines, l)
    endif
  endfor
  let l:lines = l:new_lines

  " Overwrite the original file with cleaned lines
  call writefile(l:lines, l:orig_file)

  " Delete temp file
  call delete(l:tmp_file)

  " Reload original file and save
  execute 'edit ' . fnameescape(l:orig_file)
  call setline(1, l:lines)
  echom "✅ LLM transformation complete!"
endfunction
