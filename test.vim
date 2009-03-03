function! GetScope()
	let lineNo = line('.')
	let colNo = col('.')
	let scope = ''
	let templateArgs = ''
	while 1
		if searchpair('{', '', '}', 'bW', 'synIDattr(synID(line("."), col("."), 0), "name") =~? "string\\|comment"') > 0
			call setpos('.', [0, line('.') - 1, 1, 0])
			let template = ''
			if search('template<.', 'cWe', line('.')) != 0
				let template = ParseArguments()
				let templateArgs = template . ', ' . templateArgs
				let template = '<' . DropTypes(template) . '>'
			endif
			let scope = matchstr(getline('.'), '\(class\|namespace\|struct\)\s\+\zs[a-zA-Z_][a-zA-Z0-9_]*') . template . '::' . scope
		else
			break
		endif
	endwhile
	
	call setpos('.', [0, lineNo, colNo, 0])

	return [ scope, strpart(templateArgs, 0, strlen(templateArgs) - 2) ]
endfunction

function! CheckClass()
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

function! ParseDeclaration()
	normal 1|

	let retVal = [ 0, 0, 'type', 'identifier', '' ]
	
	let scope = GetScope()
	let template = ''

	if search('template<.', 'cWe', line('.')) != 0
		let retVal[4] = ParseArguments() 
		let template = DropTypes(retVal[4])
		let retVal[1] = 1
		if scope[1] != ''
			let retVal[4] = scope[1] . ', ' . retVal[4]
		endif
	elseif scope[1] != ''
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
		
		let retVal[3] = retVal[3] . '(' . ParseArguments() . ')'

		if search('const', 'W', line('.'))
			let retVal[3] = retVal[3] . ' const'
		endif

	elseif search('[a-zA-Z_][a-zA-Z0-9_]*;', 'cW', line('.'))
		if match(modifiers, 'static') != -1 || CheckClass() == 0
			let retVal[0] = 1
		endif

		let identifierStart = col('.') - 1
		if !search('[^\S]\s', 'Wbe', line('.'))
			echo col('.')
		endif
		let retVal[2] = strpart(getline('.'), typeStart, col('.') - typeStart - 1)
		call search('[a-zA-Z_][a-zA-Z0-9_]*;', 'cWe', line('.'))
		
		let retVal[3] = scope[0] . strpart(getline('.'), identifierStart, col('.') - identifierStart - 1)
	endif

	return retVal
endfunction

function! ParseArguments()
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

function! DropTypes(arguments)
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
