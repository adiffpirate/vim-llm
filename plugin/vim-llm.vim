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
" Command: :LLMEdit 'your prompt here'
" Description: Start AI transformation based on a user-provided prompt.
" -----------------------------------------------------------------------------
" -range=% makes the command default to the whole file when no range is given.
" When you visually select and run :LLMEdit, <line1> and <line2> will be the
" visual selection boundaries and only those lines will be used.
command! -range=% -nargs=1 LLMEdit call LLMEditRun(<line1>, <line2>, <f-args>)

" -----------------------------------------------------------------------------
" Function: LLMEditRun(prompt)
" Description: Builds the LLM shell command, generates a cleaned prompt,
"              writes output to a temp file, and triggers callback.
" -----------------------------------------------------------------------------
function! LLMEditRun(range_start, range_end, user_prompt) abort
  if a:user_prompt == ''
    echoerr '❌ You must provide a prompt. Usage: :LLMEdit ''your prompt'''
    return
  endif

  let l:orig_file = expand('%:p')
  if l:orig_file == ''
    echoerr '❌ Could not get current file path.'
    return
  endif

  " Save any unsaved changes so the file on disk matches the buffer
  silent write

  " Create tmp file with extension preserved (e.g. file.llm-tmp.py)
  let l:tmp_file = substitute(l:orig_file, '\(\.[^.]*\)$', '.llm-tmp\1', '')

  " Save paths and range globally for callback use
  let g:llm_tmp_file = l:tmp_file
  let g:llm_orig_file = l:orig_file
  let g:llm_range_start = a:range_start
  let g:llm_range_end   = a:range_end

  " Build prompt from heredoc
  let l:prompt_lines =<< trim PROMPT
    You are an Senior Software Engineer expert in multiple languages.

    Your only task is to output raw code as plain text. Do not include, in any way:
        - Code fences (e.g., ```language)
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
  if exists('g:llm_model') && !empty(g:llm_model)
    let l:model_flag = '-m ' . g:llm_model . ' '
  else
    let l:model_flag = ''
  endif

  " Build the shell command that will send only the requested range to llm.
  " Uses sed -n START,ENDp to extract selected lines from the file and pipe to llm.
  let l:start = a:range_start
  let l:end   = a:range_end

  " Ensure start/end are integers and sane
  if type(l:start) != type(0) || type(l:end) != type(0)
    let l:start = 1
    let l:end = line('$')
  endif

  let l:sed_range = printf('%d,%dp', l:start, l:end)

  let l:cmd = 'sed -n ' . l:sed_range . ' ' . shellescape(l:orig_file)
        \ . ' | llm ' . l:model_flag
        \ . '-s ' . shellescape(l:prompt)
        \ . ' | tee ' . shellescape(l:tmp_file)

  " Pre-create and open the temp file in the current buffer (avoids W13 and allows live watch)
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
  let l:start = get(g:, 'llm_range_start', 1)
  let l:end   = get(g:, 'llm_range_end', line('$'))

  " Ensure temp file exists and has content
  if getfsize(l:tmp_file) <= 0
    call delete(l:tmp_file)
    execute 'edit ' . fnameescape(l:orig_file)
    execute 'noautocmd botright copen 20'
    echoerr "❌ LLM command failed. Check your model or llm CLI."
    return
  endif

  let l:lines = readfile(l:tmp_file)

  " Remove first and last code fences if present
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

  " Replace lines that are only whitespace with empty string
  let l:new_lines = []
  for l:ln in l:lines
    if l:ln =~ '^\s\+$'
      call add(l:new_lines, '')
    else
      call add(l:new_lines, l:ln)
    endif
  endfor
  let l:lines = l:new_lines

  " If user requested a range (visual selection), replace only that range.
  " Otherwise, replace the whole file (this supports the default range=% behavior).
  if type(l:start) != type(0) || type(l:end) != type(0)
    let l:start = 1
    let l:end = line('$')
  endif

  " Read the original file contents
  let l:orig_lines = readfile(l:orig_file)

  " compute zero-based indices
  let l:s_idx = l:start - 1
  let l:e_idx = l:end - 1
  let l:before = []
  let l:after = []

  if l:s_idx > 0
    let l:before = l:orig_lines[0 : l:s_idx - 1]
  endif

  if l:e_idx + 1 <= len(l:orig_lines) - 1
    let l:after = l:orig_lines[l:e_idx + 1 : ]
  endif

  " Concatenate before + new lines + after
  let l:updated = l:before + l:lines + l:after

  " Overwrite the original file with the updated contents
  call writefile(l:updated, l:orig_file)

  " Delete temp file
  call delete(l:tmp_file)

  " Reload original file in buffer and move cursor to start of replaced region
  execute 'edit ' . fnameescape(l:orig_file)
  " Place cursor at the start of the replaced region (line number l:start)
  execute printf('%d', l:start)
  echom "✅ LLM transformation complete! (lines " . l:start . " to " . l:end . ")"
endfunction
