map <buffer> <unique> <Plug>vimdecdef :call <SID>VimDecDef()<CR>

if !exists("b:buddyFile")
	let b:buddyFile = ''
endif

let b:goBack = 0

if exists("*s:GetScope")
	finish
endif

function! s:GetScope()
	let lineNo = line('.')
	let colNo = col('.')
	let scope = ''
	let templateArgs = ''
	while 1
		if searchpair('{', '', '}', 'bW', 'synIDattr(synID(line("."), col("."), 0), "name") =~? "string\\|comment"') > 0
			call setpos('.', [0, line('.') - 1, 1, 0])
			let template = ''
			if search('template<.', 'cWe', line('.')) != 0
				let template = s:ParseArguments()
				let templateArgs = template . ', ' . templateArgs
				let template = '<' . s:DropTypes(template) . '>'
			endif
			let tmpScope = matchstr(strpart(getline('.'), col('.') - 1), '\(class\|namespace\|struct\)\s\+\zs[a-zA-Z_][a-zA-Z0-9_]*')
			if tmpScope == ''
				call setpos('.', [0, lineNo, colNo, 0])
				return [ '-INVALID-', '' ]
			endif
			let scope = tmpScope . template . '::' . scope
		else
			break
		endif
	endwhile
	
	call setpos('.', [0, lineNo, colNo, 0])

	return [ scope, strpart(templateArgs, 0, strlen(templateArgs) - 2) ]
endfunction

function! s:CheckClass()
	let lineNo = line('.')
	let colNo = col('.')
	let retVal = 0
	if searchpair('{', '', '}', 'bW', 'synIDattr(synID(line("."), col("."), 0), "name") =~? "string\\|comment"') > 0
		call setpos('.', [0, line('.') - 1, 1, 0])
		if search('\(class\|struct\)\s\+\zs[a-zA-Z_][a-zA-Z0-9_]*', 'cW', line('.')) > 0
			let retVal = 1
		endif
	endif
	call setpos('.', [0, lineNo, colNo, 0])
	return retVal
endfunction

function! s:ParseDeclaration()
	normal 1|

	let retVal = [ 0, 0, 'type', 'identifier', '' ]

	if match(getline('.'), ';') == -1
		return retVal
	endif
	
	let scope = s:GetScope()

	if scope[0] == '-INVALID-'
		return retVal
	endif

	let template = ''

	if search('template<.', 'cWe', line('.')) != 0
		let retVal[4] = s:ParseArguments() 
		let template = s:DropTypes(retVal[4])
		let retVal[1] = 1
		if scope[1] != ''
			let retVal[4] = scope[1] . ', ' . retVal[4]
		endif
	elseif scope[1] != ''
		let retVal[1] = 1
		let retVal[4] = scope[1]
	endif

	let modifiers = ''
	let modifiersStart = -1
	if search('\(\(inline\|static\|virtual\|explicit\)\s\+\)\+', 'cW', line('.'))
		let modifiersStart = col('.') - 1
		call search('\(\(inline\|static\|virtual\|explicit\)\s\+\)\+', 'cWe', line('.'))
		call search('\h\s', 'Wbec', line('.'))
		let modifiers = strpart(getline('.'), modifiersStart, col('.') - modifiersStart - 1)
	endif
	call search('[a-zA-Z_~]', 'Wc', line('.'))

	let typeStart = col('.') - 1

	let operators = '+\|++\|+=\|-\|--\|-=\|\*\|\*=\|/\|/=\|%\|%=\|<\|<=\|>\|>=\|!=\|==\|!\|&&\|||\|<<\|<<=\|>>\|>>=\|\~\|&\|&=\||\||=\|^\|^=\|=\|()\|\[\]\|\*\|&\|->\|->\*\|[a-zA-Z_][a-zA-Z0-9_]\+\|,\|new\|new\s*\[\]\|delete\|delete\s*\[\]\|'
	let functionMatch = '\(operator\s*\(' . operators . '\)\|[a-zA-Z_~][a-zA-Z0-9_]*\)\s*('
	
	if search(functionMatch, 'cW', line('.')) && synIDattr(synID(line("."), col("."), 0), "name") !~? "comment\\|string"
		let retVal[0] = 1
		if match(modifiers, 'inline') != -1
			let retVal[1] = 1
		endif

		let identifierStart = col('.') - 1

		call search('[^\s]\s', 'Wbe', line('.'))
		let retVal[2] = strpart(getline('.'), typeStart, col('.') - typeStart - 1)

		call search(functionMatch . '.', 'cWe', line('.'))
		let retVal[3] = scope[0] . strpart(getline('.'), identifierStart, col('.') - identifierStart - 2)

		if template != ''
			let retVal[3] = retVal[3] . '<' . template . '>'
		endif
		
		let retVal[3] = retVal[3] . '(' . s:ParseArguments() . ')'

		if search('const', 'W', line('.'))
			let retVal[3] = retVal[3] . ' const'
		endif

	elseif search('[a-zA-Z_][a-zA-Z0-9_]*;', 'cW', line('.'))
		if match(modifiers, 'static') != -1 || s:CheckClass() == 0
			let retVal[0] = 1
		endif

		let identifierStart = col('.') - 1
		call search('[^\S]\s', 'Wbe', line('.'))
		let retVal[2] = strpart(getline('.'), typeStart, col('.') - typeStart - 1)
		call search('[a-zA-Z_][a-zA-Z0-9_]*;', 'cWe', line('.'))
		
		let retVal[3] = scope[0] . strpart(getline('.'), identifierStart, col('.') - identifierStart - 1)
	endif

	return retVal
endfunction

function! s:ParseArguments()
	let argumentsStart = col('.') - 1
	call searchpair('[<(]', '', '[>)]', 'Wc', 'synIDattr(synID(line("."), col("."), 0), "name") =~? "comment\\|string"')
	let argumentsEnd = col('.')
	let retVal = ''

	call setpos('.', [0, line('.'), argumentsStart, 0])
	while search('\s*=', 'W', line('.')) && col('.') <= argumentsEnd
		let retVal = retVal . strpart(getline('.'), argumentsStart, col('.') - argumentsStart - 1)
		call search('[,<()]', 'W', line('.') )
		if matchstr(getline('.'), '.\%>' . (col('.')) . 'c') =~ '[<(]'
			call setpos('.', [0, line('.'), col('.') + 1, 0])
			call searchpair('[(<]', '', '[)>]', 'Wc', 'synIDattr(synID(line("."), col("."), 0), "name") =~? "comment\\|string"')
			call search('[),]', 'Wc', line('.'))
			let argumentsStart = col('.')
		else
			let argumentsStart = col('.') - 1
		endif
	endwhile
	let retVal = retVal . strpart(getline('.'), argumentsStart, argumentsEnd - argumentsStart - 1)
	call setpos('.', [0, line('.'), argumentsEnd, 0])

	return retVal
endfunction

function! s:DropTypes(arguments)
	let retVal = ''
	let pos = 0

	while 1
		let strng = matchstr(a:arguments, '[a-zA-Z_][a-zA-Z0-9_]*\ze\s*\(,\|$\)', pos)
		if strng == ''
			break
		else
			let pos = match(a:arguments, '[a-zA-Z_][a-zA-Z0-9_]*\s*\zs\(,\|$\)', pos)
			let retVal = retVal . ', ' . strng
		endif
	endwhile

	return strpart(retVal, 2)
endfunction

function! s:SwapDecDef()
	let declaration = s:ParseDeclaration()
	let headerFileName =  expand("%:.")

	if declaration[0] == 1
		if declaration[1] == 1
			exec 'drop ' . fnameescape(s:GetBuddyFile())
			let b:buddyFile = headerFileName
			call s:GotoOrDropBack(declaration[3], declaration[2], declaration[4])
		else
			exec 'drop ' . fnameescape(s:GetBuddyFile())
			let b:buddyFile = headerFileName
			call s:GotoOrCreate(declaration[3], declaration[2], declaration[4])
		endif
	else
		exec 'drop ' . fnameescape(s:GetBuddyFile())
		let b:buddyFile = headerFileName
	endif
endfunction

function! s:CheckForDefinition(identifier, template)
	let lineNo = line('.')
	let colNo = col('.')
	call cursor(1, 1)

	let searchPattern = a:identifier
	if a:template != ''
		let searchPattern = 'template<' . a:template . '> ' . '.*' . searchPattern
	endif

	let retVal = search(searchPattern, 'W')

	call cursor(lineNo, colNo)

	return retVal
endfunction

function! s:GotoOrDropBack(identifier, type, template)
	let lineNo = s:CheckForDefinition(a:identifier, a:template)

	if lineNo > 0
		exec lineNo
		normal zz
	else
		exec 'drop ' . b:buddyFile
		call s:GotoOrCreate(a:identifier, a:type, a:template)
	endif
endfunction

function! s:GotoOrCreate(identifier, type, template)
	if expand("%:e") != 'cpp'
		let b:goBack = line('.')
	endif
	let lineNo = s:CheckForDefinition(a:identifier, a:template)

	if lineNo == 0
		let definition = a:type . ' ' . a:identifier
		if a:template != ''
			let definition = 'template<' . a:template . '> ' . definition
		endif
		let lineNo = line('$')
		let addEndIf = 0
		if getline(lineNo) == '#endif'
			let addEndIf = 1
		else
			let lineNo = lineNo + 2
		endif
		call setline(lineNo - 1, '')
		call setline(lineNo, definition)
		call setline(lineNo + 1, '{')
		call setline(lineNo + 2, '}')
		if addEndIf == 1
			call setline(lineNo + 3, '')
			call setline(lineNo + 4, '#endif')
		endif
	endif

	exec lineNo
	normal zz
endfunction

function! s:GetBuddyFile()
	return 'src/' . expand("%:t:r") . '.cpp'
endfunction

function! s:VimDecDef()
	if expand("%:e") == 'cpp'
		exec 'drop ' . b:buddyFile
	elseif b:goBack != 0
		exec b:goBack
		let b:goBack = 0
		normal zz
	else
		call s:SwapDecDef()
	endif
endfunction
