" FreePilot AI Code Completion Plugin for Vim/Neovim
" Version: 1.0.2
" Description: Async AI code completion with support for Ollama and OpenRouter
" Maintainer: Eddie Murphy
" License: MIT

if (has('nvim') && !has('nvim-0.5')) || (!has('nvim') && v:version < 800) || exists('g:initiated_free_pilot') || &cp
    finish
endif

let g:initiated_free_pilot = 1

"==============================================================================
" CONFIGURATION VARIABLES
"==============================================================================

" General settings
let g:free_pilot_debounce_delay = get(g:, 'free_pilot_debounce_delay', 400)

let g:free_pilot_max_suggestions = get(g:, 'free_pilot_max_suggestions', 3)
let g:free_pilot_debug = get(g:, 'free_pilot_debug', 0)
let g:free_pilot_backend = get(g:, 'free_pilot_backend', 'ollama')
let g:free_pilot_temperature = get(g:, 'free_pilot_temperature', 0.1)
let g:free_pilot_log_file = get(g:, 'free_pilot_log_file', '')
let g:free_pilot_max_tokens = get(g:, 'free_pilot_max_tokens', 120)

" Ollama specific settings
let g:free_pilot_ollama_model = get(g:, 'free_pilot_ollama_model', 'llama3.2:latest')
let g:free_pilot_ollama_url = get(g:, 'free_pilot_ollama_url', 'http://localhost:11434/api/generate')

" OpenRouter specific settings
let g:free_pilot_openrouter_api_key = get(g:, 'free_pilot_openrouter_api_key', '')
let g:free_pilot_openrouter_model = get(g:, 'free_pilot_openrouter_model', 'anthropic/claude-2:1')
let g:free_pilot_openrouter_site_url = get(g:, 'free_pilot_openrouter_site_url', 'https://github.com/whatever555/free-pilot-vim')
let g:free_pilot_openrouter_site_name = get(g:, 'free_pilot_openrouter_site_name', 'Vim AI Complete Plugin')

" Default auto-start setting (can be overridden in vimrc)
let g:free_pilot_autostart = get(g:, 'free_pilot_autostart', 1)
" Default included filetypes (empty means all filetypes)
let g:free_pilot_include_filetypes = get(g:, 'free_pilot_include_filetypes', [])
" Default excluded filetypes
let g:free_pilot_exclude_filetypes = get(g:, 'free_pilot_exclude_filetypes', [
    \ 'help',
    \ 'netrw',
    \ 'NvimTree',
    \ 'TelescopePrompt',
    \ 'fugitive',
    \ 'gitcommit',
    \ 'quickfix',
    \ 'prompt'
    \ ])

"==============================================================================
" STATE VARIABLES
"==============================================================================

" Initialize state variables only once
if !exists('s:init_done')
    let s:init_done = 1
    let s:completion_items = []
    let s:request_counter = 0
    let s:jobs = {}
    let s:responses = {}
    let s:current_request_id = 0
    let s:timer_id = -1
    let s:current_job_output = []
    let s:last_trigger_mode = ''
endif

"==============================================================================
" COMPLETION SETUP
"==============================================================================

function! s:SetupCompletionOptions()
    " Configure completion behavior
    set completeopt=menu,menuone,noinsert,noselect
    
    " Reduce noise in completion experience
    if exists('+shortmess')
        set shortmess+=c
    endif
endfunction

"==============================================================================
" VALIDATION AND STATUS
"==============================================================================

function! s:CheckBackendStatus()
    if g:free_pilot_backend == 'openrouter' && empty(g:free_pilot_openrouter_api_key)
        call s:Debug("OpenRouter API key not set. Please set g:free_pilot_openrouter_api_key in your vimrc.", 1)
        return 0
    endif
    
    if g:free_pilot_backend == 'ollama'
        " Test Ollama connection
        let l:test_cmd = printf('curl -s -X GET %s/api/tags 2>&1', g:free_pilot_ollama_url)
        let l:result = system(l:test_cmd)
        if v:shell_error
            call s:Debug("Ollama connection failed. Is Ollama running?", 1)
            return 0
        endif
    endif
    
    return 1
endfunction

"==============================================================================
" DEBUG LOGGING
"==============================================================================

function! s:Debug(msg, ...)
    let override = get(a:, 1, 0)
    if g:free_pilot_debug || override
        " Truncate long messages in echo
        let l:display_msg = a:msg
        if len(l:display_msg) > 100
            let l:display_msg = l:display_msg[0:97] . "..."
        endif
        
        echom "AI-Complete-Debug: " . l:display_msg
        
        " Log to file if configured
        if !empty(g:free_pilot_log_file)
            let l:log_msg = strftime("%Y-%m-%d %H:%M:%S") . ": " . a:msg
            call writefile([l:log_msg], g:free_pilot_log_file, "a")
        endif
    endif
endfunction

" Perform initial setup
call s:SetupCompletionOptions()
call s:Debug("Plugin initialized with " . g:free_pilot_backend . " backend")




"==============================================================================
" UTILITY FUNCTIONS AND JOB HANDLING
"==============================================================================

" Check for job support
function! s:HasJobSupport()
    return has('nvim') ? exists('*jobstart') : has('job') && has('channel')
endfunction

" Ensure response tracking exists
function! s:EnsureResponseExists(request_id) abort
    if !exists('s:responses')
        let s:responses = {}
    endif
    if !has_key(s:responses, a:request_id)
        let s:responses[a:request_id] = {
            \ 'output': [],
            \ 'done': 0,
            \ 'chunks': []
        \ }
    endif
endfunction

" Check if job exists
function! s:JobExists(job_id) abort
    if has('nvim')
        return jobwait([a:job_id], 0)[0] == -1
    else
        if has_key(s:jobs, a:job_id)
            try
                let l:job = s:jobs[a:job_id].job
                let l:status = job_status(l:job)
                return l:status == 'run'
            catch
                return 0
            endtry
        endif
        return 0
    endif
endfunction


" Execute async request with proper job handling
function! s:ExecuteAsyncRequest(cmd, request_id, temp_file, backend, context) abort
    try
        call s:EnsureResponseExists(a:request_id)
        
        if has('nvim')
            let l:callbacks = {
                \ 'on_stdout': function('s:HandleNvimJobOutput'),
                \ 'on_stderr': function('s:HandleNvimJobOutput'),
                \ 'on_exit': function('s:HandleNvimJobExit'),
                \ 'request_id': a:request_id,
                \ 'temp_file': a:temp_file,
                \ 'backend': a:backend,
                \ 'context': a:context,
                \ 'chunks': []
                \ }
            
            let l:job_id = jobstart(a:cmd, l:callbacks)
            if l:job_id <= 0
                call s:Debug("Failed to start Neovim job")
                return 0
            endif
            return l:job_id
        else
            " Vim job handling - fixed version
            let l:options = {}
            
            " Set output callback
            function! s:OutCallback(channel, msg) closure
                call s:HandleVimJobOutput(a:channel, a:msg, 'stdout')
            endfunction
            let l:options['out_cb'] = function('s:OutCallback')
            
            " Set error callback
            function! s:ErrCallback(channel, msg) closure
                call s:HandleVimJobOutput(a:channel, a:msg, 'stderr')
            endfunction
            let l:options['err_cb'] = function('s:ErrCallback')
            
            " Set exit callback
            function! s:ExitCallback(job, status) closure
                let l:ctx = {'request_id': a:request_id, 'temp_file': a:temp_file, 'backend': a:backend, 'context': a:context}
                call s:HandleVimJobExit(a:job, a:status, l:ctx)
            endfunction
            let l:options['exit_cb'] = function('s:ExitCallback')
            
            " Start the job with options
            let l:job = job_start(a:cmd, l:options)
            
            " Get job ID for tracking
            let l:job_id = ch_info(job_getchannel(l:job)).id
            
            " Store job and context for later reference
            let s:jobs[l:job_id] = {
                \ 'job': l:job,
                \ 'request_id': a:request_id,
                \ 'temp_file': a:temp_file,
                \ 'backend': a:backend,
                \ 'context': a:context,
                \ 'chunks': []
                \ }
                
            return l:job_id
        endif
    catch
        call s:Debug("Error in ExecuteAsyncRequest: " . v:exception)
        return 0
    endtry
endfunction

" Neovim job output handler
function! s:HandleNvimJobOutput(job_id, data, event) dict abort
    try
        call s:EnsureResponseExists(self.request_id)
        if a:event == 'stdout' || a:event == 'stderr'
            let l:valid_data = filter(copy(a:data), '!empty(v:val)')
            if !empty(l:valid_data)
                call extend(s:responses[self.request_id].output, l:valid_data)
                call s:Debug("Received chunk of size: " . len(join(l:valid_data, "\n")))
            endif
        endif
    catch
        call s:Debug("Error in HandleNvimJobOutput: " . v:exception)
    endtry
endfunction

" Neovim job exit handler
function! s:HandleNvimJobExit(job_id, data, event) dict abort
    try
        call s:EnsureResponseExists(self.request_id)
        let l:request_id = self.request_id
        
        call s:Debug("Job for request #" . l:request_id . " exited with status " . a:data)
        let s:responses[l:request_id].done = 1
        
        if l:request_id == s:current_request_id
            let l:response = join(s:responses[l:request_id].output, '')
            if !empty(l:response)
                try
                    let l:clean_response = substitute(l:response, '\r\n\|\r', '\n', 'g')
                    call s:Debug("Got response for request #" . l:request_id)
                    
                    if self.backend == 'ollama'
                        call s:ProcessOllamaResponse(l:clean_response, self.context)
                    else
                        call s:ProcessOpenRouterResponse(l:clean_response, self.context)
                    endif
                catch
                    call s:Debug("Error processing response: " . v:exception)
                endtry
            endif
        endif
        
        " Cleanup
        if filereadable(self.temp_file)
            call delete(self.temp_file)
        endif
        if has_key(s:responses, l:request_id)
            unlet s:responses[l:request_id]
        endif
    catch
        call s:Debug("Error in HandleNvimJobExit: " . v:exception)
    endtry
endfunction





" Vim job output handler
function! s:HandleVimJobOutput(channel, msg, type) abort
    try
        let l:job = ch_getjob(a:channel)
        let l:job_id = ch_info(a:channel).id
        
        if has_key(s:jobs, l:job_id)
            call add(s:jobs[l:job_id].chunks, a:msg)
        endif
    catch
        call s:Debug("Error in HandleVimJobOutput: " . v:exception)
    endtry
endfunction

" Vim job exit handler (updated)
function! s:HandleVimJobExit(job, status, ctx) abort
    try
        let l:channel = job_getchannel(a:job)
        let l:job_id = ch_info(l:channel).id
        
        call s:Debug("Job for request #" . a:ctx.request_id . " exited with status " . a:status)
        
        if has_key(s:jobs, l:job_id)
            let l:response = join(s:jobs[l:job_id].chunks, "\n")
            
            if a:ctx.request_id == s:current_request_id
                if a:ctx.backend == 'ollama'
                    call s:ProcessOllamaResponse(l:response, a:ctx.context)
                elseif a:ctx.backend == 'openrouter'
                    call s:ProcessOpenRouterResponse(l:response, a:ctx.context)
                endif
            endif
            
            " Cleanup
            call delete(a:ctx.temp_file)
            call remove(s:jobs, l:job_id)
        endif
    catch
        call s:Debug("Error in HandleVimJobExit: " . v:exception)
    endtry
endfunction

" Cleanup helpers
function! s:CleanupJob(job_id) abort
    if has_key(s:jobs, a:job_id)
        let l:job_data = s:jobs[a:job_id]
        if has_key(l:job_data.options, 'temp_file')
            call delete(l:job_data.options.temp_file)
        endif
        call remove(s:jobs, a:job_id)
    endif
endfunction

function! s:CleanupResponse(request_id) abort
    if has_key(s:responses, a:request_id)
        unlet s:responses[a:request_id]
    endif
endfunction

" Show completions in the menu
function! s:ShowCompletions(items, context) abort
    if empty(a:items) || mode() != 'i'
        return
    endif
    
    try
        let l:formatted_items = []
        let l:prefix = a:context.current_line
        let l:prefix_len = len(l:prefix)
        
        for l:item in a:items
            if empty(l:item)
                continue
            endif
            
            " Clean the suggestion
            let l:clean_item = substitute(l:item, '[[:cntrl:]]', '', 'g')
            let l:clean_item = substitute(l:clean_item, '\n\|\r', '', 'g')
            let l:clean_item = substitute(l:clean_item, '^\s*\(.\{-}\)\s*$', '\1', '')
            
            " Check if the completion starts with what the user has already typed
            " and remove the duplication if it exists
            if !empty(l:prefix) && l:clean_item =~# '^' . l:prefix
                let l:clean_item = l:clean_item[l:prefix_len:]
            endif
            
            if !empty(l:clean_item)
                call add(l:formatted_items, {
                    \ 'word': l:clean_item,
                    \ 'menu': '[AI]',
                    \ 'icase': 1,
                    \ 'dup': 0,
                    \ 'empty': 1,
                    \ 'user_data': 'free_pilot'
                    \ })
            endif
        endfor
        
        if !empty(l:formatted_items)
            " Set completion options for better reliability
            set completeopt=menu,menuone,noinsert
            
            " Start completion
            call complete(col('.'), l:formatted_items)
            
            " Set up autocommand to restore completeopt
            augroup FreePilotInsert
                autocmd!
                autocmd CompleteDone * call s:HandleCompleteDone()
            augroup END
        endif
    catch
        call s:Debug("Error in ShowCompletions: " . v:exception)
    endtry
endfunction

" Handle completion done
function! s:HandleCompleteDone() abort
    " Restore user's completeopt setting if they had one
    if exists('g:free_pilot_saved_completeopt')
        let &completeopt = g:free_pilot_saved_completeopt
    endif
    
    " Clean up
    augroup FreePilotInsert
        autocmd!
    augroup END
endfunction



" Get file context for AI prompts
function! s:GetFileContext()
    let l:cur_line_num = line('.')
    let l:cur_col = col('.')
    let l:lines = getline(1, '$')
    
    " Mark cursor position in current line
    let l:cur_line = l:lines[l:cur_line_num - 1]
    let l:before_cursor = strpart(l:cur_line, 0, l:cur_col - 1)
    let l:after_cursor = strpart(l:cur_line, l:cur_col - 1)
    let l:lines[l:cur_line_num - 1] = l:before_cursor . '|CURSOR|' . l:after_cursor
    
    return {
        \ 'full_file': join(l:lines, "\n"),
        \ 'current_line': l:before_cursor,
        \ 'after_cursor': l:after_cursor,
        \ 'line_number': l:cur_line_num,
        \ 'column': l:cur_col,
        \ 'filetype': &filetype
        \ }
endfunction






"==============================================================================
" OPENROUTER IMPLEMENTATION
"==============================================================================

" Main OpenRouter request handler
function! s:MakeOpenRouterRequest(context, request_id) abort
    if empty(g:free_pilot_openrouter_api_key)
        call s:Debug("ERROR: OpenRouter API key not set", 1)
        return
    endif

    " Create system and user messages
    let [l:system_message, l:user_message] = s:CreateOpenRouterMessages(a:context)
    
    " Construct the API request
    let l:request = s:BuildOpenRouterRequest(l:system_message, l:user_message)
    
    " Execute the request
    call s:ExecuteOpenRouterRequest(l:request, a:request_id)
endfunction

" Create messages for OpenRouter
function! s:CreateOpenRouterMessages(context) abort
    " System message defines the AI's role and behavior
    let l:system_message = join([
        \ "You are a code completion AI that provides ONLY direct code continuations.",
        \ "Never explain or comment - return ONLY code that fits at the cursor position.",
        \ "Each completion must be on a new line.",
        \ "Completions must be contextually relevant and syntactically valid."
    \ ], " ")

    " User message provides context and requirements
    let l:user_message = printf(
        \ "Complete this %s code from the cursor position (marked as |CURSOR|).\n" .
        \ "Current line: %s|CURSOR|%s\n\n" .
        \ "Rules:\n" .
        \ "1. Provide exactly %d different completions\n" .
        \ "2. Each completion on a new line\n" .
        \ "3. Only return text that should appear at |CURSOR|\n" .
        \ "4. No formatting, explanation, or markdown\n" .
        \ "5. Must be syntactically valid\n" .
        \ "6. Context:\n```%s\n%s\n```",
        \ a:context.filetype,
        \ a:context.current_line,
        \ a:context.after_cursor,
        \ g:free_pilot_max_suggestions,
        \ a:context.filetype,
        \ a:context.full_file
    \ )

    return [l:system_message, l:user_message]
endfunction

" Build OpenRouter request object
function! s:BuildOpenRouterRequest(system_message, user_message) abort
    return {
        \ 'model': g:free_pilot_openrouter_model,
        \ 'messages': [
            \ {
                \ 'role': 'system',
                \ 'content': a:system_message
            \ },
            \ {
                \ 'role': 'user',
                \ 'content': a:user_message
            \ }
        \ ],
        \ 'temperature': g:free_pilot_temperature,
        \ 'max_tokens': g:free_pilot_max_tokens,
        \ 'top_p': 0.95,
        \ 'presence_penalty': 0.1,
        \ 'frequency_penalty': 0.1,
        \ 'stop': ["|", "```", "Example", "Note", "Here"]
    \ }
endfunction

" Execute OpenRouter request
function! s:ExecuteOpenRouterRequest(request, request_id) abort
    let l:json_data = json_encode(a:request)
    let l:temp_file = tempname()
    call writefile([l:json_data], l:temp_file)
    
    " Get context for current request
    let l:context = s:GetFileContext()
    
    let l:cmd = [
        \ 'curl',
        \ '-sS',
        \ '-X',
        \ 'POST',
        \ 'https://openrouter.ai/api/v1/chat/completions',
        \ '-H', 'Content-Type: application/json',
        \ '-H', 'Authorization: Bearer ' . g:free_pilot_openrouter_api_key,
        \ '-H', 'HTTP-Referer: ' . g:free_pilot_openrouter_site_url,
        \ '-H', 'X-Title: ' . g:free_pilot_openrouter_site_name,
        \ '-d', '@' . l:temp_file
    \ ]

    " Execute async request with context
    let l:job_id = s:ExecuteAsyncRequest(l:cmd, a:request_id, l:temp_file, 'openrouter', l:context)
    if l:job_id <= 0
        call delete(l:temp_file)
        call s:Debug("Failed to start OpenRouter request")
    endif
endfunction



" Process OpenRouter response
function! s:ProcessOpenRouterResponse(response_text, context) abort
    try
        call s:Debug("Processing OpenRouter response")
        let l:data = json_decode(a:response_text)
        
        if type(l:data) == v:t_dict && has_key(l:data, 'error')
            call s:Debug("OpenRouter API Error: " . string(l:data.error))
            return
        endif
        
        let l:suggestions = []
        if type(l:data) == v:t_dict && has_key(l:data, 'choices')
            for l:choice in l:data.choices
                if has_key(l:choice, 'message') && has_key(l:choice.message, 'content')
                    let l:content = l:choice.message.content
                    
                    for l:line in split(l:content, '\n')
                        let l:cleaned = s:CleanCompletionText(l:line)
                        if !empty(l:cleaned)
                            call add(l:suggestions, l:cleaned)
                        endif
                    endfor
                endif
            endfor
        endif
        
        if !empty(l:suggestions)
            call s:ShowCompletions(l:suggestions[:g:free_pilot_max_suggestions-1], a:context)
        else
            call s:Debug("No valid suggestions found in OpenRouter response")
        endif
    catch
        call s:Debug("Error processing OpenRouter response: " . v:exception)
    endtry
endfunction




" Clean completion text
function! s:CleanCompletionText(text) abort
    let l:cleaned = a:text
    
    " Remove common prefixes
    let l:cleaned = substitute(l:cleaned, '^\s*\(```\w*\)\?\s*', '', '')
    let l:cleaned = substitute(l:cleaned, '^\s*[0-9.]\+\s*', '', '')
    let l:cleaned = substitute(l:cleaned, '^\s*[-*•]\s*', '', '')
    
    " Remove markdown code markers
    let l:cleaned = substitute(l:cleaned, '`\(.\{-}\)`', '\1', 'g')
    
    " Remove cursor marker
    let l:cleaned = substitute(l:cleaned, '|CURSOR|', '', 'g')
    
    " Trim whitespace
    let l:cleaned = substitute(l:cleaned, '^\s*\(.\{-}\)\s*$', '\1', '')
    
    " Skip if it starts with common text patterns we don't want
    if l:cleaned =~? '\v^(Note|Here|Example|This)'
        return ''
    endif
    
    return l:cleaned
endfunction





"==============================================================================
" OLLAMA IMPLEMENTATION
"==============================================================================

" Main Ollama request handler
function! s:MakeOllamaRequest(context, request_id) abort
    " Create the prompt
    let l:prompt = s:CreateOllamaPrompt(a:context)
    
    " Build the request object
    let l:request = s:BuildOllamaRequest(l:prompt)
    
    " Execute the request
    call s:ExecuteOllamaRequest(l:request, a:request_id)
endfunction

" Create prompt for Ollama
function! s:CreateOllamaPrompt(context) abort
    return printf(
        \ "You are a code completion AI. Complete the code at the cursor position.\n" .
        \ "Current position: %s|CURSOR|%s\n\n" .
        \ "STRICT RULES:\n" .
        \ "1. ONLY provide completions that continue from |CURSOR|\n" .
        \ "2. Each completion must be ONE LINE only\n" .
        \ "3. Return EXACTLY %d different completions\n" .
        \ "4. NO formatting, NO explanation, NO markdown\n" .
        \ "5. Each completion on a new line\n" .
        \ "6. Evaluate context to provide relevant completions\n" .
        \ "7. Must be syntactically valid %s code\n\n" .
        \ "Context:\n```%s\n%s```\n\n" .
        \ "EXAMPLES:\n" .
        \ "For 'co|CURSOR|': nst MAX_VALUE = 100\n" .
        \ "For 'fun|CURSOR|': ction calculateTotal()\n" .
        \ "For 'let x|CURSOR|': = getMappedValue()\n\n" .
        \ "RESPOND WITH COMPLETIONS ONLY:",
        \ a:context.current_line,
        \ a:context.after_cursor,
        \ g:free_pilot_max_suggestions,
        \ a:context.filetype,
        \ a:context.filetype,
        \ a:context.full_file
    \ )
endfunction

" Build Ollama request object
function! s:BuildOllamaRequest(prompt) abort
    return {
        \ 'model': g:free_pilot_ollama_model,
        \ 'prompt': a:prompt,
        \ 'stream': v:false,
        \ 'raw': v:true,
        \ 'options': {
            \ 'temperature': g:free_pilot_temperature,
            \ 'top_p': 0.95,
            \ 'top_k': 40,
            \ 'num_predict': 60,
            \ 'stop': ["|", "```", "Example", "Note", "Here", "*", "-", "1.", "2.", "3."]
        \ }
    \ }
endfunction

" Execute Ollama request
function! s:ExecuteOllamaRequest(request, request_id) abort
    " Convert request to JSON and save to temp file
    let l:json_data = json_encode(a:request)
    let l:temp_file = tempname()
    call writefile([l:json_data], l:temp_file)
    
    " Get context for current request
    let l:context = s:GetFileContext()
    
    " Construct curl command
    let l:cmd = [
        \ 'curl',
        \ '-s',
        \ g:free_pilot_ollama_url,
        \ '-H', 'Content-Type: application/json',
        \ '-d', '@' . l:temp_file
    \ ]

    " Execute async request with context
    let l:job_id = s:ExecuteAsyncRequest(l:cmd, a:request_id, l:temp_file, 'ollama', l:context)
    if l:job_id <= 0
        call delete(l:temp_file)
        call s:Debug("Failed to start Ollama request")
    endif
endfunction



" Process Ollama response
function! s:ProcessOllamaResponse(response_text, context) abort
    try
        call s:Debug("Processing Ollama response")
        
        let l:data = json_decode(a:response_text)
        
        if type(l:data) != v:t_dict || !has_key(l:data, 'response')
            call s:Debug("Invalid Ollama response format")
            return
        endif
        
        let l:completion_text = l:data.response
        let l:suggestions = s:ExtractOllamaSuggestions(l:completion_text)
        
        if !empty(l:suggestions)
            call s:ShowCompletions(l:suggestions[:g:free_pilot_max_suggestions-1], a:context)
        else
            call s:Debug("No valid suggestions found in Ollama response")
        endif
    catch
        call s:Debug("Error processing Ollama response: " . v:exception)
    endtry
endfunction





" Extract suggestions from Ollama response
function! s:ExtractOllamaSuggestions(completion_text) abort
    let l:suggestions = []
    
    " First try splitting by newlines
    let l:lines = split(a:completion_text, '\n')
    for l:line in l:lines
        let l:cleaned = s:CleanOllamaSuggestion(l:line)
        if !empty(l:cleaned)
            call add(l:suggestions, l:cleaned)
        endif
    endfor
    
    " If no suggestions found, try splitting by commas
    if empty(l:suggestions) && a:completion_text =~ ','
        let l:parts = split(a:completion_text, ',\s*')
        for l:part in l:parts
            let l:cleaned = s:CleanOllamaSuggestion(l:part)
            if !empty(l:cleaned)
                call add(l:suggestions, l:cleaned)
            endif
        endfor
    endif
    
    " If still no suggestions but we have content, use it directly
    if empty(l:suggestions) && !empty(a:completion_text)
        let l:cleaned = s:CleanOllamaSuggestion(a:completion_text)
        if !empty(l:cleaned)
            call add(l:suggestions, l:cleaned)
        endif
    endif
    
    return l:suggestions
endfunction

" Clean Ollama suggestion
function! s:CleanOllamaSuggestion(text) abort
    let l:cleaned = a:text
    
    " Remove common prefixes
    let l:cleaned = substitute(l:cleaned, '^\s*\(```\w*\)\?\s*', '', '')
    let l:cleaned = substitute(l:cleaned, '^\s*[0-9.]\+\s*', '', '')
    let l:cleaned = substitute(l:cleaned, '^\s*[-*•]\s*', '', '')
    
    " Remove markdown code markers
    let l:cleaned = substitute(l:cleaned, '`\(.\{-}\)`', '\1', 'g')
    
    " Remove cursor marker
    let l:cleaned = substitute(l:cleaned, '|CURSOR|', '', 'g')
    
    " Trim whitespace
    let l:cleaned = substitute(l:cleaned, '^\s*\(.\{-}\)\s*$', '\1', '')
    
    " Skip if it starts with common text patterns we don't want
    if l:cleaned =~? '\v^(Note|Here|Example|This)'
        return ''
    endif
    
    return l:cleaned
endfunction

" Test Ollama connection
function! s:TestOllamaConnection()
    let l:test_request = {
        \ 'model': g:free_pilot_ollama_model,
        \ 'prompt': 'Test connection',
        \ 'stream': v:false
    \ }
    
    let l:json_data = json_encode(l:test_request)
    let l:temp_file = tempname()
    call writefile([l:json_data], l:temp_file)
    
    let l:cmd = printf('curl -s %s -H "Content-Type: application/json" -d @%s',
        \ g:free_pilot_ollama_url,
        \ l:temp_file)
    
    let l:response = system(l:cmd)
    call delete(l:temp_file)
    
    if v:shell_error
        echo "Ollama connection failed: " . l:response
        return 0
    else
        echo "Ollama connection successful!"
        return 1
    endif
endfunction





"==============================================================================
" TRIGGER AND COMPLETION HANDLING
"==============================================================================

" Trigger completion after debounce
function! s:TriggerCompletion() abort
    " Only trigger in insert mode
    if mode() != 'i'
        return
    endif
    
    " Check if completion is enabled for this buffer
    if !exists('b:free_pilot_enabled') || !b:free_pilot_enabled
        return
    endif
    
    " Verify backend status
    if !s:CheckBackendStatus()
        return
    endif
    
    call s:Debug("Triggering completion")
    
    " Stop existing timer if any
    if s:timer_id != -1
        call timer_stop(s:timer_id)
        call s:Debug("Stopped existing timer")
    endif
    
    " Store current mode
    let s:last_trigger_mode = mode()
    
    " Start new timer
    let s:timer_id = timer_start(
        \ g:free_pilot_debounce_delay,
        \ function('s:DebouncedComplete')
    \ )
    call s:Debug("Started new timer: " . s:timer_id)
endfunction

" Handle completion after debounce
function! s:DebouncedComplete(timer_id) abort
    " Verify we're still in insert mode
    if mode() != 'i'
        call s:Debug("No longer in insert mode, skipping completion")
        return
    endif
    
    call s:Debug("Starting completion request using " . g:free_pilot_backend)
    
    " Get context
    let l:context = s:GetFileContext()
    
    " Generate new request ID
    let s:request_counter += 1
    let l:request_id = s:request_counter
    let s:current_request_id = l:request_id
    
    call s:Debug("Created request #" . l:request_id . " for line " . l:context.line_number)
    
    " Cancel any running jobs
    call s:CancelRunningJobs()
    
    " Reset output collection
    let s:current_job_output = []
    
    " Make request based on backend
    if g:free_pilot_backend == 'ollama'
        call s:MakeOllamaRequest(l:context, l:request_id)
    else
        call s:MakeOpenRouterRequest(l:context, l:request_id)
    endif
endfunction

" Cancel running jobs
function! s:CancelRunningJobs() abort
    for l:job_id in keys(s:jobs)
        if s:JobExists(str2nr(l:job_id))
            if has('nvim')
                call jobstop(str2nr(l:job_id))
            else
                let l:job = s:jobs[l:job_id].job
                call job_stop(l:job)
            endif
            call s:Debug("Stopped job " . l:job_id)
        endif
        call remove(s:jobs, l:job_id)
    endfor
endfunction


"==============================================================================
" BUFFER MANAGEMENT
"==============================================================================

" Check if filetype should have completion enabled
function! s:ShouldEnableForFiletype(filetype) abort
    " Check exclude list first
    if index(g:free_pilot_exclude_filetypes, a:filetype) >= 0
        return 0
    endif
    
    " If include list is empty, allow all filetypes (except excluded)
    if empty(g:free_pilot_include_filetypes)
        return 1
    endif
    
    " Check include list
    return index(g:free_pilot_include_filetypes, a:filetype) >= 0
endfunction

" Enable completion for current buffer
function! s:EnableComplete() abort
    if !s:CheckBackendStatus()
        return
    endif
    
    " Check if this filetype should be enabled
    if !s:ShouldEnableForFiletype(&filetype)
        call s:Debug("AI completion not enabled for filetype: " . &filetype)
        let b:free_pilot_enabled = 0
        return
    endif
    
    let b:free_pilot_enabled = 1
    call s:Debug("Enabled AI completion for buffer")
endfunction

" Disable completion for current buffer
function! s:DisableComplete() abort
    let b:free_pilot_enabled = 0
    call s:Debug("Disabled AI completion for buffer")
endfunction

"==============================================================================
" COMMANDS AND AUTOCOMMANDS
"==============================================================================

" Define commands
command! FreePilotEnable call s:EnableComplete()
command! FreePilotDisable call s:DisableComplete()
command! FreePilotToggle let b:free_pilot_enabled = !get(b:, 'free_pilot_enabled', 0) | 
    \ echo "AI completion " . (b:free_pilot_enabled ? "enabled" : "disabled")
command! FreePilotToggleDebug let g:free_pilot_debug = !g:free_pilot_debug | 
    \ echo "AI debug: " . (g:free_pilot_debug ? "ON" : "OFF")

" Backend switching commands
command! FreePilotSetBackendOllama let g:free_pilot_backend = 'ollama' | 
    \ call s:Debug("Switched to Ollama backend", 1)
command! FreePilotSetBackendOpenRouter let g:free_pilot_backend = 'openrouter' | 
    \ call s:Debug("Switched to OpenRouter backend", 1)

" Model setting command
command! -nargs=1 FreePilotSetModel call s:SetModel(<q-args>)

" Testing commands
command! FreePilotTestOllama call s:TestOllamaConnection()
command! FreePilotTrigger call s:TriggerCompletion()

" Status command
command! FreePilotStatus call s:ShowStatus()

" Set model helper
function! s:SetModel(model) abort
    if g:free_pilot_backend == 'ollama'
        let g:free_pilot_ollama_model = a:model
        call s:Debug("Set Ollama model to " . g:free_pilot_ollama_model, 1)
    else
        let g:free_pilot_openrouter_model = a:model
        call s:Debug("Set OpenRouter model to " . g:free_pilot_openrouter_model, 1)
    endif
endfunction

" Show status
function! s:ShowStatus() abort
    echo "AI Complete Status:"
    echo "-------------------"
    echo "Backend: " . g:free_pilot_backend
    echo "Model: " . (g:free_pilot_backend == 'ollama' ? g:free_pilot_ollama_model : g:free_pilot_openrouter_model)
    echo "Debug: " . (g:free_pilot_debug ? "ON" : "OFF")
    echo "Buffer enabled: " . get(b:, 'free_pilot_enabled', 0)
    echo "Debounce delay: " . g:free_pilot_debounce_delay . "ms"
    echo "Max suggestions: " . g:free_pilot_max_suggestions
    echo "Temperature: " . g:free_pilot_temperature
endfunction


"==============================================================================
" AUTOCOMMANDS
"==============================================================================


" Save user's completeopt setting when plugin loads
let g:free_pilot_saved_completeopt = &completeopt


" Set up autocommands
augroup FreePilot
    autocmd!
    
    " Auto-enable for new buffers based on configuration
    autocmd BufNewFile,BufRead * if g:free_pilot_autostart | call s:EnableComplete() | endif
    
    " Trigger completion on text change in insert mode
    autocmd TextChangedI,TextChangedP * call s:TriggerCompletion()
    
    " Handle insert mode entry
    autocmd InsertEnter * if exists('b:free_pilot_enabled') && b:free_pilot_enabled | 
        \ set completeopt=menu,menuone,noinsert |
        \ endif
    
    " Handle insert mode exit
    autocmd InsertLeave * if exists('g:free_pilot_saved_completeopt') |
        \ let &completeopt = g:free_pilot_saved_completeopt |
        \ endif
augroup END


"==============================================================================
" INITIALIZATION
"==============================================================================

" Enable completion for current buffer on plugin load
call s:EnableComplete()

" Log initialization
call s:Debug("Plugin initialized with " . g:free_pilot_backend . " backend")
if g:free_pilot_backend == 'ollama'
    call s:Debug("Using Ollama model: " . g:free_pilot_ollama_model)
else
    call s:Debug("Using OpenRouter model: " . g:free_pilot_openrouter_model)
endif
