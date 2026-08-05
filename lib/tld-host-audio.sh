#!/usr/bin/env bash

if ! declare -F tld_init_paths >/dev/null 2>&1 || ! declare -F tld_process_stop >/dev/null 2>&1; then
  source "${BASH_SOURCE[0]%/*}/tld-common.sh"
  source "${BASH_SOURCE[0]%/*}/tld-process.sh"
fi

_tld_audio_lib_dir=${BASH_SOURCE[0]%/*}
if [[ "$_tld_audio_lib_dir" == "${BASH_SOURCE[0]}" ]]; then
  _tld_audio_lib_dir=.
fi

_tld_audio_error() {
  printf 'audio: %s\n' "$*" >&2
  return 1
}

_tld_audio_endpoint() {
  printf '%s\n' "${PULSE_SERVER_DEFAULT:-tcp:127.0.0.1:4713}"
}

_tld_audio_sink() {
  printf '%s\n' "${PULSE_SINK_DEFAULT:-AAudio_sink}"
}

tld_audio_is_ready() {
  local endpoint sink result

  tld_require_command pactl || return 1
  endpoint=$(_tld_audio_endpoint)
  sink=$(_tld_audio_sink)
  if PULSE_SERVER="$endpoint" pactl info >/dev/null 2>&1; then
    result=0
  else
    result=1
  fi
  TLD_AUDIO_READY_ENDPOINT="$endpoint"
  TLD_AUDIO_READY_SINK="$sink"
  return "$result"
}

_tld_audio_record_owner() {
  local owner="${1-}"
  local record_file

  record_file="${TLD_STATE_DIR:?TLD_STATE_DIR must be initialized}/audio-owner.env"
  printf 'AUDIO_OWNER=%s\n' "$owner" > "$record_file.tmp.$$"
  mv -f -- "$record_file.tmp.$$" "$record_file"
}

tld_audio_start() {
  local endpoint sink pid command_hash record_file
  local result=0

  tld_require_command pactl || return 1
  tld_require_command pulseaudio || return 1
  endpoint=$(_tld_audio_endpoint)
  sink=$(_tld_audio_sink)

  if tld_audio_is_ready; then
    _tld_audio_record_owner external || return 1
    TLD_AUDIO_OWNER=external
    printf 'PASS audio endpoint=%s owner=external\n' "$endpoint"
    return 0
  fi

  record_file="${TLD_STATE_DIR:?TLD_STATE_DIR must be initialized}/processes/audio.env"
  if [[ -e "$record_file" ]] && tld_process_is_owned audio; then
    _tld_audio_record_owner owned || return 1
    TLD_AUDIO_OWNER=owned
    printf 'PASS audio endpoint=%s owner=owned(recorded)\n' "$endpoint"
    return 0
  fi

  if ! pulseaudio --daemonize --exit-idle-time=-1 \
    --load="module-native-protocol-tcp auth-anonymous=1 auth-ip-acl=127.0.0.1 port=4713"; then
    _tld_audio_error "cannot start PulseAudio daemon on $endpoint"
    return 1
  fi

  pid=$(pgrep -x pulseaudio | head -n 1) || {
    _tld_audio_error 'PulseAudio daemon started but no pulseaudio PID was found'
    return 1
  }
  if ! [[ "$pid" =~ ^[1-9][0-9]*$ ]]; then
    _tld_audio_error "invalid PulseAudio PID after start: $pid"
    return 1
  fi
  if ! command_hash=$(tr '\0' '\n' < "${TLD_PROC_ROOT:-/proc}/$pid/cmdline" | sha256sum | awk '{print $1}'); then
    _tld_audio_error 'cannot hash PulseAudio command line'
    return 1
  fi
  if ! tld_process_record audio "$pid" "$command_hash"; then
    _tld_audio_error 'cannot record owned PulseAudio process'
    return 1
  fi
  _tld_audio_record_owner owned || result=1
  TLD_AUDIO_OWNER=owned

  local attempts=0
  while (( attempts < 20 )); do
    if tld_audio_is_ready; then
      printf 'PASS audio endpoint=%s owner=owned pid=%s\n' "$endpoint" "$pid"
      return "$result"
    fi
    attempts=$((attempts + 1))
    sleep 0.5
  done

  _tld_audio_error "PulseAudio did not become ready at $endpoint within ten seconds"
  if tld_audio_stop_if_owned; then
    :
  else
    _tld_audio_error 'owned PulseAudio process could not be cleaned up after readiness failure'
  fi
  return 1
}

tld_audio_stop_if_owned() {
  local owner record_file

  record_file="${TLD_STATE_DIR:?TLD_STATE_DIR must be initialized}/audio-owner.env"
  owner=external
  if [[ -f "$record_file" && ! -L "$record_file" ]]; then
    owner=$(sed -n 's/^AUDIO_OWNER=//p' "$record_file" | tail -n 1)
  fi
  if [[ "$owner" == 'owned' ]]; then
    if tld_process_stop audio; then
      rm -f -- "$record_file" || true
      TLD_AUDIO_OWNER=stopped
      printf '%s\n' 'PASS audio owner=owned stopped'
      return 0
    fi
    _tld_audio_error 'owned PulseAudio process could not be verified stopped'
    return 1
  fi
  printf '%s\n' 'PASS audio owner=external left running'
  return 0
}

tld_audio_status() {
  local endpoint sink result=0

  endpoint=$(_tld_audio_endpoint)
  sink=$(_tld_audio_sink)
  if tld_audio_is_ready; then
    printf 'PASS audio endpoint=%s sink=%s\n' "$endpoint" "$sink"
    return 0
  fi
  printf 'WARN audio endpoint=%s is not reachable; run desktop-start to start the toolkit audio path\n' "$endpoint"
  return 1
}
