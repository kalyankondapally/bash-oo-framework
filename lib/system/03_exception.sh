alias throw="__EXCEPTION_TYPE__='MANUALLY INVOKED' command_not_found_handle"

command_not_found_handle() {
    # USE DEFAULT IFS IN CASE IT WAS CHANGED - important!
    local IFS=$' \t\n'
    
    # ignore the error from the catch subshell itself
    if [[ "$*" = '( set -e; true'* ]]
    then
        return 0
    fi

    local script="${BASH_SOURCE[1]#./}"
    local lineNo="${BASH_LINENO[0]}"
    local undefinedObject="$*"
    local type="${__EXCEPTION_TYPE__:-"UNDEFINED COMMAND"}"

    local merger=''
    if [[ ! "$type" = " " ]]
    then
        merger=': '
    fi

    if [[ $__oo__insideTryCatch -gt 0 ]]
    then
        Log.Debug 3 "inside Try No.: $__oo__insideTryCatch"

        if [[ ! -f /tmp/stored_exception_line ]]; then
            echo "$lineNo" > /tmp/stored_exception_line
        fi
        if [[ ! -f /tmp/stored_exception ]]; then
            echo "$undefinedObject" > /tmp/stored_exception
        fi
        if [[ ! -f /tmp/stored_exception_source ]]; then
            echo "$script" > /tmp/stored_exception_source
        fi
        if [[ ! -f /tmp/stored_exception_backtrace ]]; then
            Exception.DumpBacktrace 2 > /tmp/stored_exception_backtrace
        fi
        
        return 1 # needs to be return 1
    fi

    if [[ $BASH_SUBSHELL -ge 25 ]]
    then
        echo "ERROR: Call stack exceeded (25)."
        Exception.ContinueOrBreak || exit 1
    fi

    local -a exception=( "$lineNo" "$undefinedObject" "$script" )
    
    local IFS=$'\n'
    for traceElement in $(Exception.DumpBacktrace 2)
    do
        exception+=( "$traceElement" )
    done
    IFS=$' \t\n'

    Log.Write
    Log.Write " $(UI.Color.Red)$(UI.Powerline.Fail) $(UI.Color.Bold)UNCAUGHT EXCEPTION${merger}$(UI.Color.LightRed)${type}$(UI.Color.Default)"
    Exception.PrintException "${exception[@]}"

    Exception.ContinueOrBreak
}

Exception.PrintException() {
    @params exception
    
    local -i backtraceIndentationLevel=${backtraceIndentationLevel:-0}
    
    local -i counter=0
    local -i backtraceNo=0
    
    local -a backtraceLine
    local -a backtraceCommand
    local -a backtraceFile
    
    #for traceElement in Exception.GetLastException
    while [[ $counter -lt ${#exception[@]} ]]
    do
        backtraceLine[$backtraceNo]="${exception[$counter]}"
        counter+=1
        backtraceCommand[$backtraceNo]="${exception[$counter]}"
        counter+=1
        backtraceFile[$backtraceNo]="${exception[$counter]}"
        counter+=1
        
        backtraceNo+=1
    done
    
    local -i index=1
    
    while [[ $index -lt $backtraceNo ]]
    do
        Log.Write "$(Exception.FormatExceptionSegment "${backtraceFile[$index]}" "${backtraceLine[$index]}" "${backtraceCommand[($index - 1)]}" $(( $index + $backtraceIndentationLevel )) )"
        index+=1
    done
}

Exception.CanHighlight() {
    @var errLine
    @var stringToMark
    
    local stringToMarkWithoutSlash="$(String.ReplaceSlashes "$stringToMark")"
    errLine="$(String.ReplaceSlashes "$errLine")"
    
    if [[ "$errLine" == *"$stringToMarkWithoutSlash"* ]]
    then
        return 0
    else
        return 1
    fi
}

Exception.HighlightPart() {
    @var errLine
    @var stringToMark
    
    # Workaround for a Bash bug that causes string replacement to fail when a \ is in the string
    local stringToMarkWithoutSlash="$(String.ReplaceSlashes "$stringToMark")"
    errLine="$(String.ReplaceSlashes "$errLine")"
    
    local underlinedObject="$(Exception.GetUnderlinedPart "$stringToMark")"
    local underlinedObjectInLine="${errLine/$stringToMarkWithoutSlash/$underlinedObject}"

    # Bring back the slash:
    underlinedObjectInLine="$(String.BringBackSlashes "$underlinedObjectInLine")"
    
    # Trimming:
    underlinedObjectInLine="${underlinedObjectInLine#"${underlinedObjectInLine%%[![:space:]]*}"}" # "

	echo "$underlinedObjectInLine"
}

Exception.GetUnderlinedPart() {
    @var stringToMark
    
    echo "$(UI.Color.LightGreen)$(UI.Powerline.RefersTo) $(UI.Color.Magenta)$(UI.Color.Underline)$stringToMark$(UI.Color.White)$(UI.Color.NoUnderline)"
}

Exception.FormatExceptionSegment() {
    @var script
    @int lineNo
    @var stringToMark
    @int callPosition=1

    local errLine="$(sed "${lineNo}q;d" "$script")"
    local originalErrLine="$errLine"
    
    local -i linesTried=0
    
    # In case it's a multiline eval, sometimes bash gives a line that's offset by a few
    while [[ $linesTried -lt 5 && $lineNo -gt 0 ]] && ! Exception.CanHighlight "$errLine" "$stringToMark"
    do
        linesTried+=1
        lineNo+=-1
        errLine="$(sed "${lineNo}q;d" "$script")"
    done

    # Cut out the path, leave the script name
    script="${script##*/}"
    
    local prefix="   $(UI.Powerline.Branch)$(String.GetXSpaces $(($callPosition * 3 - 3)) || true) "
    
    if [[ $linesTried -ge 5 ]]
    then
        # PRINT THE ORGINAL OBJECT AND ORIGINAL LINE #
        #local underlinedObject="$(Exception.HighlightPart "$errLine" "$stringToMark")"
        local underlinedObject="$(Exception.GetUnderlinedPart "$stringToMark")"
        echo "${prefix}$(UI.Color.White)${underlinedObject}$(UI.Color.Default) [$(UI.Color.Blue)${script}:${lineNo}$(UI.Color.Default)]"
        prefix="$prefix$(UI.Powerline.Fail) "
        errLine="$originalErrLine"
    fi
    
    local underlinedObjectInLine="$(Exception.HighlightPart "$errLine" "$stringToMark")"
    
    echo "${prefix}$(UI.Color.White)${underlinedObjectInLine}$(UI.Color.Default) [$(UI.Color.Blue)${script}:${lineNo}$(UI.Color.Default)]"
}

Exception.ContinueOrBreak()
{
    ## TODO: Exceptions that happen in commands that are piped to others do not HALT the execution
    ## TODO: Add a workaround for this ^

    # if in a terminal
    if [ -t 0 ]
    then
        Log.Write
        Log.Write " $(UI.Color.Yellow)$(UI.Powerline.Lightning)$(UI.Color.White) Press $(UI.Color.Bold)[CTRL+C]$(UI.Color.White) to exit or $(UI.Color.Bold)[Return]$(UI.Color.White) to continue execution."
        read -s
        Log.Write " $(UI.Color.Blue)$(UI.Powerline.Cog)$(UI.Color.White) Continuing...$(UI.Color.Default)"
        return 0
        Log.Write
    else
        Log.Write
        exit 1
    fi
}

Exception.DumpBacktrace()
{
    @int startFrom=1
    # inspired by: http://stackoverflow.com/questions/64786/error-handling-in-bash
    
    # USE DEFAULT IFS IN CASE IT WAS CHANGED - important!
    local IFS=$' \t\n'
    
    local -i i=0

    while caller $i > /dev/null
    do
        if (( $i + 1 >= $startFrom ))
        then
            local -a trace=( $(caller $i) )
            
            echo "${trace[0]}"
            echo "${trace[1]}"
            echo "${trace[@]:2}"
        fi
        i+=1
    done
}
