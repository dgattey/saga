# Zsh completion for the 'run' command in the Saga repo
# Run 'run bootstrap' to install, or add manually to .zshrc:
#   source ~/checkouts/saga/scripts/completions.zsh

# Completion function
_run() {
    local curcontext="$curcontext" state
    
    # Only works if ./run exists in current directory
    [[ -x "./run" ]] || return 1
    
    if (( CURRENT == 2 )); then
        # Complete script names
        compadd $(./run --completions 2>/dev/null)
    elif (( CURRENT >= 3 )); then
        # Complete script-specific options
        local script="${words[2]}"
        compadd $(./run "$script" --completions 2>/dev/null)
    fi
}

# Shell function wrapper that calls ./run
run() {
    ./run "$@"
}

# Register the completion function for 'run'
compdef _run run
