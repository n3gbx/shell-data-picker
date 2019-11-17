#! /bin/bash

# ANSI control sequences (CSI sequences)
# octal ASCII codes for general keys
declare -r ESC=$(printf "\033")
declare -r ENTER=$(printf "\012")
declare -r BACKSPACE=$(printf "\127")
declare -r TAB=$(printf "\011")
declare -r SPACE=$(printf "\040")

# escape sequances for navigation keys
declare -r UP="${ESC}[A"
declare -r DOWN="${ESC}[B"
declare -r RIGHT="${ESC}[C"
declare -r LEFT="${ESC}[D"

# constant menu actions
declare -r act_exit="/.."
declare -r act_more=".."
declare -r entry_null="--"

# number of entries to display per page
page_capacity=5
# entries to display
declare -a entries
# picked entries indexes in entries array
declare -a picked_entries_idxs
# default current page
declare -i page_curr=1
# menu header
menu_header="Menu"


# read script options
while getopts d:h:c: FLAG; do
	case $FLAG in
		d)	
			IFS=';' read -r -a entries <<< "$OPTARG"
			;;
		h)
			menu_header="$OPTARG"
			;;
		c)
			if [[ $OPTARG =~ [[:digit:]] ]]; then
				if [[ $OPTARG -le 10 && $OPTARG -gt 0 ]]; then
					page_capacity=$OPTARG
				fi
			fi
			;;
    	\?)
     		echo -e "Option not allowed"\\n
     		exit 1
    		;;
  	esac
done
shift $(( OPTIND - 1 ))


# app app width and height
declare -r width=25
declare -r height=20

# terminal dimensions ROW COL
# border area dimensions
declare -a term_size=($(tput lines) $(tput cols))

declare -r bord_start=(0 0)
declare -r bord_end=(${height} ${width})
# menu area dimensions
declare -r menu_start=($((bord_start[0] + 1)) $((bord_start[1] + 2)))
declare -r menu_end=($((bord_end[0] - 1)) $((bord_end[1] - 1)))
# helper area dimensions
declare -r help_start=(${menu_start[@]})
declare -r help_end=(${help_start[0]} ${menu_end[1]} )
# header area dimensions
declare -r head_start=($((help_start[0] + 2)) $((help_start[1] + 1)))
declare -r head_end=(${head_start[0]} $width)
# list area dimensions
declare -r list_start=($((head_start[0] + 2)) $((head_start[1] - 1)))
declare -r list_end=($((list_start[0] + page_capacity + 1)) $width)
# entries area dimensions
declare -r entry_start=($((list_start[0] + 1)) ${list_start[1]})
declare -r entry_end=($((list_end[0] - 1)) $width)

set_entries_for_curr_page() {
	local total_entries_size=${#entries[@]}
	local end=$(( page_curr * page_capacity ))
	local begin=$(( end - page_capacity ))
	declare -g page_entries=()
	for (( i = $begin; i < $end; i++ )); do
		local e="${entries[$i]}"
		if [[ $i -lt $total_entries_size ]]; then
			if [[ "${#entries}" -gt 15 ]]; then
				e=$(echo "${e:0:12}...")
			fi
			page_entries+=("$e")
		else break;
		fi
	done
	declare -g page_entries_count=${#page_entries[@]}

	# update last entryion index bases on entries page size
	declare -g last_entry_idx=$(( page_entries_count - 1 ))
}

# returns global entryion index
# by the index widthin the current page number
get_entry_global_idx() {
	local page_curr_idx=$(( page_curr - 1 ))
	local first_page_entry_idx=$(( page_curr_idx * page_capacity ))
	echo $(( first_page_entry_idx + $1 ))
}

set_pages_count() {
	local count=$(( ${#entries[@]} / $page_capacity ))
	if [[ $(( ${#entries[@]} % $page_capacity )) -ne 0 ]]; then ((count++)); fi
	declare -g pages_count=$count
}

# cursor, screen and line related functions
get_term_name() { tput longname; }
get_term_rows() { tput lines; }
get_term_cols() { tput cols; }
get_term_colors() { tput colors; }
cur_save() { tput sc; } # \e7
cur_res() { tput rc; } # \e8
cur_home() { tput home; } # \e[H
cur_move() { tput cup $1 ${2:-1}; } # \e[x;yH
cur_down() { tput cud1; }
cur_up() { tput cuu1; }
cur_center() { tput cup $((height/2)) $((width/2)); }
cur_invis() { tput civis; } # \e[?25l
cur_vis() { tput cvvis; } # \e[?25h
cur_norm() { tput cnorm; }
scr_save() { tput smcup; }
scr_res() { tput rmcup; }
scr_clr_end() { tput ed; }
scr_clr_all() { tput clear; }
ln_clr_end() { tput el; } # \e[0K
ln_clr_beg() { tput el1; } # \e[1K
ln_clr_all() { tput el2; } # \e[2K
ln_clr_to() { local n=$(get_term_cols); printf "%${1:-$n}s" ""; }
ln_clr_from_to() { cur_save; cur_move $1; ln_clr_to $2; cur_res; }


# general text attributes modifying
atr_rst() { printf "\e[0m"; }
bold() { printf "\e[1m${*}\e[21m"; }
dim() { printf "\e[2m${*}\e[22m"; }
under() { printf "\e[4m${*}\e[24m"; }
blink() { printf "\e[5m${*}\e[25m"; }
invert() { printf "\e[7m${*}\e[27m"; }


draw() {

	before_exit() { clear; printf '\033[?25h'; printf '\033[0m'; }
	# local draw() functions
	print_pagination() {
		[[ ${pages_count} -gt 1 ]] && printf "[${page_curr}..${pages_count}]"
	}

	# cursor
	set_cursor_pos() { printf "${ESC}[$1;${2:-1}H"; }
	get_cursor_pos() { IFS=';' read -sdR -p $'\E[6n' ROW COL; echo ${ROW#*[}; }
	unset_cursor() { printf "${ESC}[?25l"; }

	# entries
	print_entry_order() { printf "${2:-${EMPTY}}${1}${EMPTY}"; }
	printf_entry_prefix() { printf "${1:-" "}"; }
	print_selected_entry() { printf "\e[46;30m%-${entry_end[1]}s\e[0m\n" "$1"; }
	print_default_entry() { printf "%-${entry_end[1]}s\n" "$1"; }
	set_picked_entry() { picked_entries_idxs+=($1); }
	unset_picked_entry() {
		local entry="$1"
		for idx in "${!picked_entries_idxs[@]}"; do
			[[ "${picked_entries_idxs[$idx]}" == "$entry" ]] &&
				unset picked_entries_idxs[$idx];
		done
	}
	is_picked_idxs_includes() {
		local match="$1"
  		for e in "${picked_entries_idxs[@]}"; do
  			[[ "$e" == "$match" ]] && return 0;
  		done
  		return 1
	}
	clear_entries_page() {
		tput sc
		set_cursor_pos ${list_start[@]}
		for i in $(seq $((page_capacity + 2))); do
			tput el; tput cud1; 
		done
		tput rc
	}
	draw_header() {
		tput sc
		set_cursor_pos ${head_start[@]};
		printf "$EMPTY$menu_header $(print_pagination)"
		tput rc
	}

	tput smcup
	clear
	# calc number of pages 
	set_pages_count
	# disable user input
	stty -echo
	# disable cursor blinking
	unset_cursor

	# restore terminal cursor and colors if script interrupted
	trap "stty echo > /dev/null 2>&1; exit;" EXIT
	trap "stty echo > /dev/null 2>&1; printf '\033[?25h'; printf '\033[0m';" SIGINT

	local input;
	# inital entries start row
	local start_row=${entry_start[0]}
	local curr_entry_idx=0

	while true; do

		# initial setup or if the page was changed
		if [[ $prev_page_num -ne $page_curr ]]; then
			# clear entries page to prevent content ovelapping
			clear_entries_page	
			# update array of entries for current page
			set_entries_for_curr_page
			# reset selection position to the top of the list
			if [[ $prev_page_num -gt $page_curr ]]; then
				curr_entry_idx=$last_entry_idx
			else 
				curr_entry_idx=0
			fi
			# draw/re-draw pagination
			draw_header

			set_cursor_pos ${list_start[@]}
			if [[ $page_curr -ne 1 ]]; then echo " $act_more"
			else echo " $act_exit"; fi
		fi
		
		# draw/re-draw menu
		(for (( i = 0; i < $page_capacity; i++ )); do

			set_cursor_pos $(( start_row + i )) ${entry_start[1]}

			local curr_order=$((i + 1))
			local curr_entry=${page_entries[$i]}

			if [[ $i -ge ${#page_entries[@]} ]]; then
				printf_entry_prefix
				print_default_entry "$entry_null"
				continue
			fi

			if is_picked_idxs_includes $(get_entry_global_idx $i); then
				printf_entry_prefix "+"
			else
				printf_entry_prefix
			fi

			if [[ $i -eq $curr_entry_idx ]]; then
				print_selected_entry "$curr_entry"
			else
				print_default_entry "$curr_entry"
			fi

			if [[ $i -eq 4 ]]; then
				set_cursor_pos ${list_end[0]} ${list_start[1]}
				echo " $act_more"
			fi
		done)

		# remember current page number as previous
		local prev_page_num=$page_curr;

		# read user input
		while true; do
			# read 1 byte to listen user input
			# used to prevent problems width escape symbols listening
      		read -rsn1 input

      		if [[ "$input" =~ [[:digit:]] ]]; then break; fi
			if [[ "$input" == "$ENTER" ]]; then break; fi
      		if [[ "$input" == "$ESC" ]]; then
        		# read 2 more bytes, assuming it an escape sequance
        		read -rsn2 -t 0.0001
        		# concat read bytes width an escape character
        		input+="$REPLY"
        		if [[ "$input" == "$UP" ]]; then break; fi
        		if [[ "$input" == "$DOWN" ]]; then break; fi
        		if [[ "$input" == "$LEFT" ]]; then break; fi
        		if [[ "$input" == "$RIGHT" ]]; then break; fi
        		if [[ "$input" == "$ESC" ]]; then break; fi		
      		fi   		
    	done

		# do things with menu navigation
		case $input in
        	$UP)
				if [[ $curr_entry_idx -eq 0 ]]; then
					if [[ $page_curr -ne 1 ]]; then
						(( page_curr-- ))
					fi
				else (( curr_entry_idx-- )); fi
				;;
        	$DOWN)

				if [[ $curr_entry_idx -eq $last_entry_idx ]]; then
					if [[ $page_curr -ne $pages_count ]]; then
						((page_curr++))
					fi
				else ((curr_entry_idx++)); fi
        		;;
        	$RIGHT)
				global_idx=$(get_entry_global_idx $curr_entry_idx)
				
				if is_picked_idxs_includes $global_idx; then
					unset_picked_entry ${global_idx}
				else
					set_picked_entry ${global_idx}
				fi
				;;
			$ENTER)
				if [[ ${#picked_entries_idxs[@]} -eq 0 ]]; then
					set_picked_entry $(get_entry_global_idx $curr_entry_idx)
				fi

				before_exit

				picked_entries=()
				for idx in "${picked_entries_idxs[@]}"; do
					picked_entries+=("${entries[$idx]}")
				done

				IFS=$";"; echo -n "${picked_entries[*]}" >&2 

				break;
				;;
			$ESC)
				before_exit
				exit
				;;
			[1-${#page_entries[@]}])
				# need to decrease chosen number because arrays starts width 0
				curr_entry_idx=$(($input - 1))
				global_idx=$(get_entry_global_idx $curr_entry_idx)
				
				if is_picked_idxs_includes $global_idx; then
					unset_picked_entry ${global_idx}
				else
					set_picked_entry ${global_idx}
				fi
				;;
    	esac
	done
}

draw 2>&1 1>/dev/tty
