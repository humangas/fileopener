#!/usr/bin/env bash

_FO_APPNAME="fo"
_FO_VERSION="0.0.1"
_FO_FIND_OPTIONS="-type d -name .git -prune -o -type f -print"
_FO_FIND_PIPE_CMD="" #e.g. egrep \.go 
_FO_GREP_CMD="ag"
_FO_GREP_OPTIONS="--hidden --ignore .git/ . "
#_FO_GREP_OPTIONS="--hidden --ignore .git/ -v '^\n' _FILE"
_FO_CONFIRM_OPEN_FILE_CNT=5


function _usage() {
echo "usage: $_FO_APPNAME [global options] [options] [path]
version: $_FO_VERSION

options:
    --grep, -g    Open in grep mode

path:
    nothing       If not specified, files under the current directory are targeted.
    directory     If you specify a directory, files under that directory are targeted.
    file          If you specify a file, simply open it.

global options:
   --help, -h     Show help
   --version      Show version
"
}

function _version(){
    echo "$_FO_APPNAME $_FO_VERSION"
}

function isText() {
    local filepath="$1"
    [[ -z $filepath ]] && return 1

    local type=$(file "$filepath" | cut -d: -f2 | grep 'text')
    [[ -z $type ]] && return 1
    [[ ${#type} -ne 0 ]] && return 0

    return 1
}

function _main() {
    local spath
    for opt in "$@"; do
        case "$opt" in
            '-h'|'--help') _usage && exit 0 ;;
            '--version')   _version && exit 0 ;;
            '-g'|'--grep') 
                if [[ -z $spath ]]; then
                    shift 1; spath=$1
                fi
                _grep "$spath"; exit $? ;;
            -*) 
                echo "Error $opt is no such option"
                echo "--> more info with: $_FO_APPNAME --help"
                exit 1
                ;;
            *)
                if [[ ! -e $opt ]]; then
                    echo "Error $opt is not found"
                    exit 1
                fi
                spath=$opt
                ;;
        esac
    done

    main "$@"
    exit $?
}

function _grep() {
    local spath=${1:-$PWD}
    local _grep_options="$_FO_GREP_OPTIONS $f"

    (
        cd $spath
        local line=$(eval $_FO_GREP_CMD $_grep_options \
            | fzf-tmux --tac \
                --bind=ctrl-u:half-page-up,ctrl-d:half-page-down,ctrl-y:yank \
                --expect=ctrl-f)
        [[ -z $line ]] && main $spath && return
        [[ $line =~ ^ctrl-f\s*.* ]] && main $spath && return

        local file
        local num
        file=$(printf $line | cut -d: -f1)
        num=$(printf $line | cut -d: -f2)
        
        vim -c $num $spath/$file
    )
}

function main() {
    [[ ! -z "$_FO_FIND_PIPE_CMD" ]] && _FO_FIND_PIPE_CMD="| $_FO_FIND_PIPE_CMD"

    local spath=${1:-$PWD}
    if [[ -f $spath ]]; then
        isText $spath && vim $spath || open $spath
        return
    fi

    local select
    IFS=$'\n' select=($(eval find $spath $_FO_FIND_OPTIONS $_FO_FIND_PIPE_CMD \
        | sed -e "s@$spath/@@" \
        | fzf-tmux --multi --cycle \
        --preview "less -R $spath/{}" \
        --bind=ctrl-a:select-all,ctrl-a:toggle-all,ctrl-u:half-page-up,ctrl-d:half-page-down,ctrl-y:yank \
        --expect=enter,ctrl-f \
    ))

    key=$(head -1 <<< "$select")
    file=$(head -2 <<< "$select" | tail -1)
    declare files="${select[@]:1}"

    declare -a filesx
    for f in $files; do
        isText "$spath/$f" && filesx+=($f)
    done

    _filesearch $spath $key $((${#filesx[@]}))
}

function _filesearch() {
    local spath=$1
    local key=$2
    local scnt=$3

    case $key in
        enter)
            [[ -z ${files[@]} ]] && return

            local _open_file_cnt=$((${#select[@]}-1))
            if [[ $_open_file_cnt -gt $_FO_CONFIRM_OPEN_FILE_CNT ]]; then
                echo -n "Really open $_open_file_cnt files? [Y/n]: "
                read ans
                case $ans in
                    'Y'|'yes') ;;
                    *) main $spath && return ;;
                esac
            fi

            declare -a vimfiles
            declare -a etcfiles
            echo "Open the following file..."

            for f in $files; do
                echo "$spath/$f"
                isText $spath/${f}
                retval=$?
                [[ $retval -eq 0 ]] && vimfiles+=($spath/${f}) || etcfiles+=($spath/${f})
            done

            [[ $((${#etcfiles[@]})) -ge 1 ]] && open ${etcfiles[@]}
            [[ $((${#vimfiles[@]})) -ge 1 ]] && vim ${vimfiles[@]}
            ;;

        ctrl-f)
            [[ -z ${filesx[@]} ]] && main $spath && return

            declare -a _target_files
            for f in $files; do
                _target_files+=($f)
                _target_files+=("|")
            done

            local _grep_options
            if [[ $scnt -gt 1 ]]; then
                local ag_gop=$(echo "'${_target_files[@]:0:((${#_target_files[@]}-1))}'" | sed -e 's/ //g')
                _grep_options="-G $ag_gop $_FO_GREP_OPTIONS"
            else
                _grep_options="$_FO_GREP_OPTIONS $f"
            fi

            (
                cd $spath
                local line=$(eval $_FO_GREP_CMD $_grep_options \
                    | fzf-tmux --tac \
                        --bind=ctrl-u:half-page-up,ctrl-d:half-page-down,ctrl-y:yank \
                        --expect=ctrl-f)
                [[ -z $line ]] && main $spath && return
                [[ $line =~ ^ctrl-f\s*.* ]] && main $spath && return

                local file
                local num
                if [[ $scnt -gt 1 ]]; then
                    file=$(printf $line | cut -d: -f1)
                    num=$(printf $line | cut -d: -f2)
                else
                    file=${filesx[@]}
                    num=$(printf $line | cut -d: -f1)
                fi

                vim -c $num $spath/$file
            )
            ;;

        *)
            return
            ;;
    esac
}

# main
_main "$@"