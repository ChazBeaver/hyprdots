
# /* ---- 💫 https://github.com/JaKooLit 💫 ---- */  ##
# For Rofi Beats to play online Music or Locally save media files

# Directory local music folder
mDIR="$HOME/Music/"

# Directory for icons
iDIR="$HOME/.config/swaync/icons"

# Online Stations. Edit as required
declare -A online_music=(
  ["Lofi Radio 🎧🎶"]="https://play.streamafrica.net/lofiradio"
  ["Chillwave Radio 🎧🎶"]="https://play.streamafrica.net/chillwave"
  ["Video Game Radio 🎧🎶"]="https://play.streamafrica.net/gameradio"
  ["Reggae Radio 🎧🎶"]="https://play.streamafrica.net/reggaerepublic"
  ["Anime Radio 🎧🎶"]="https://play.streamafrica.net/weebanimeradio"
  ["XRock Radio 🎧🎶"]="https://play.streamafrica.net/xrockradio"
  ["Country Radio 🎧🎶"]="https://play.streamafrica.net/hitscountry"
  ["Jazz Radio 🎧🎶"]="https://play.streamafrica.net/radiojazz"
  ["Dancehall Radio 🎧🎶"]="https://play.streamafrica.net/mashupradio"
  ["Oldtime Radio 🎧🎶"]="https://play.streamafrica.net/oldtimeradio"
  ["Comedy Radio 🎧🎶"]="https://play.streamafrica.net/laughnetwork"
  ["KPop Radio 🎧🎶"]="https://play.streamafrica.net/kpopradio"
  ["Pop Dance Radio 🎧🎶"]="https://play.streamafrica.net/popmusicdance"
  ["Rain and Thunder Naturesounds Radio 🎧🎶"]="https://play.streamafrica.net/rainandthunder"
  ["Hip Hop Classics Radio 🎧🎶"]="https://play.streamafrica.net/radio6hiphop"
  ["Japan City Pop Radio 🎧🎶"]="https://play.streamafrica.net/japancitypop"
  ["Rap Radio 🎧🎶"]="https://play.streamafrica.net/afrofusionrap"
  ["Dreamscapes Radio 🎧🎶"]="https://play.streamafrica.net/dreamscapes"
  ["Classical Radio 🎧🎶"]="https://play.streamafrica.net/classicalradio"
  ["Chillhop - stream.zeno.fm 🎧🎶"]="http://stream.zeno.fm/fyn8eh3h5f8uv"
  # THESE STILL WORK
  # ["FM - Easy Rock 96.3 📻🎶"]="https://radio-stations-philippines.com/easy-rock"
  # ["FM - Love Radio 90.7 📻🎶"]="https://radio-stations-philippines.com/love"
  # ["FM - Fresh Philippines 📻🎶"]="https://onlineradio.ph/553-fresh-fm.html"
  # ["FM - WRock - CEBU 96.3 📻🎶"]="https://onlineradio.ph/126-96-3-wrock.html"
  # ISSUE PLAYING YOUTUBE RIGHT NOW
  # ["YT - Wish 107.5 YT Pinoy HipHop 📻🎶"]="https://youtube.com/playlist?list=PLkrzfEDjeYJnmgMYwCKid4XIFqUKBVWEs&si=vahW_noh4UDJ5d37"
  # ["YT - Wish 107.5 YT Wishclusives 📹🎶"]="https://youtube.com/playlist?list=PLkrzfEDjeYJn5B22H9HOWP3Kxxs-DkPSM&si=d_Ld2OKhGvpH48WO"
  # ["YT - Relaxing Music 📹🎶"]="https://youtube.com/playlist?list=PLMIbmfP_9vb8BCxRoraJpoo4q1yMFg4CE"
  # ["YT - Relaxing Piano Jazz Music 🎹🎶"]="https://youtu.be/85UEqRat6E4?si=jXQL1Yp2VP_G6NSn"
  # ["YT - Relaxing Spooky Halloween Music 2024 🎃🎶"]="https://www.youtube.com/watch?v=zbmiarkSY3I"
  # ["YT - ChillSynth FM - lofi synthwave radio🎶"]="https://www.youtube.com/watch?v=UedTcufyrHc"
  # ["YT - Chillwave FM: Retro Synth 🎶"]="https://www.youtube.com/watch?v=qnStVGoIgBA"
  # ["YT - Tokyo Night Drive - lofi hiphop beats 🌃🎶"]="https://www.youtube.com/watch?v=Lcdi9O2XB4E"
  # ["YT - Lofi Girl 🎧🎶"]="https://www.youtube.com/watch?v=jfKfPfyJRdk"
  # ["YT - Peaceful Piano Radio 🎹🎶"]="https://www.youtube.com/watch?v=TtkFsfOP9QI"
  # ["YT - Tavern Music: DnD, Fantasy, Inn 🔮🎶"]="https://www.youtube.com/watch?v=vK5VwVyxkbI"
  # ["YT - Fiesta Latina Mix 2024 💃🎶"]="https://www.youtube.com/watch?v=dE4xDQbS-9c"
  # ["YT - Ambient Space - Study, Sleep, Meditate🎶"]="https://www.youtube.com/watch?v=MUWu45U2bMU"
)

# Populate local_music array with files from music directory and subdirectories
populate_local_music() {
  local_music=()
  filenames=()
  while IFS= read -r file; do
    local_music+=("$file")
    filenames+=("$(basename "$file")")
  done < <(find "$mDIR" -type f \( -iname "*.mp3" -o -iname "*.flac" -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.mp4" \))
}

# Function for displaying notifications
notification() {
  notify-send -u normal -i "$iDIR/music.png" "Playing: $@"
}

# Main function for playing local music
play_local_music() {
  populate_local_music

  # Prompt the user to select a song
  choice=$(printf "%s\n" "${filenames[@]}" | rofi -i -dmenu -config ~/.config/rofi/config-rofi-Beats.rasi -p "Local Music")

  if [ -z "$choice" ]; then
    exit 1
  fi

  # Find the corresponding file path based on user's choice and set that to play the song then continue on the list
  for (( i=0; i<"${#filenames[@]}"; ++i )); do
    if [ "${filenames[$i]}" = "$choice" ]; then
		
	    notification "$choice"

      # Play the selected local music file using mpv
      mpv --playlist-start="$i" --loop-playlist --vid=no  "${local_music[@]}"

      break
    fi
  done
}

# Main function for shuffling local music
shuffle_local_music() {
  notification "Shuffle local music"

  # Play music in $mDIR on shuffle
  mpv --shuffle --loop-playlist --vid=no "$mDIR"
}

# Main function for playing online music
play_online_music() {
  choice=$(printf "%s\n" "${!online_music[@]}" | rofi -i -dmenu -config ~/.config/rofi/config-rofi-Beats.rasi -p "Online Music")

  if [ -z "$choice" ]; then
    exit 1
  fi

  link="${online_music[$choice]}"

  notification "$choice"
  
  # Play the selected online music using mpv
  mpv --shuffle --vid=no "$link"
}

# Check if an online music process is running and send a notification, otherwise run the main function
pkill mpv && notify-send -u low -i "$iDIR/music.png" "Music stopped" || {

# Prompt the user to choose between local and online music
user_choice=$(printf "Play from Online Stations\nPlay from Music Folder\nShuffle Play from Music Folder" | rofi -dmenu -config ~/.config/rofi/config-rofi-Beats-menu.rasi -p "Select music source")

  case "$user_choice" in
    "Play from Music Folder")
      play_local_music
      ;;
    "Play from Online Stations")
      play_online_music
      ;;
    "Shuffle Play from Music Folder")
      shuffle_local_music
      ;;
    *)
      echo "Invalid choice"
      ;;
  esac
}
